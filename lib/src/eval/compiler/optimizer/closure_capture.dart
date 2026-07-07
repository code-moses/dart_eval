import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Identifies closures that should capture a snapshot copy of their enclosing
/// frame (via `PushFunctionPtrCopyCapture`) instead of a live reference.
///
/// dart_eval closures capture the enclosing stack frame by reference. For a
/// closure created inside a loop that reads a loop-scoped variable, that is
/// incorrect: all iterations share one frame, so every closure observes the
/// last value written to the variable's slot (or an unrelated value once the
/// slot is reused) instead of the per-iteration binding that Dart semantics
/// require. Copying the frame at closure creation approximates the
/// per-iteration binding.
///
/// Copying is only safe when the closure never assigns to a captured
/// variable, since an assignment would write to the snapshot and be invisible
/// to the enclosing scope. Closures that write to captured variables keep the
/// existing reference-capture behavior.
Set<int> findCopyCaptureClosures(Declaration d) {
  final visitor = _ClosureCaptureVisitor();
  d.accept(visitor);
  return visitor.result;
}

class _Decl {
  _Decl(this.scopeIndex, this.inLoop);

  final int scopeIndex;

  /// Whether the variable is freshly bound on each iteration of an enclosing
  /// loop (loop variables and variables declared in loop bodies)
  final bool inLoop;
}

class _Closure {
  _Closure(this.offset, this.baseScope);

  final int offset;

  /// Scope depth of the closure's own parameter scope; declarations at
  /// shallower depths are captured from enclosing scopes
  final int baseScope;

  var capturesLoopVariable = false;
  var writesCapturedVariable = false;
}

class _ClosureCaptureVisitor extends RecursiveAstVisitor<void> {
  final result = <int>{};

  final _scopes = <Map<String, _Decl>>[{}];
  final _closures = <_Closure>[];
  var _loopDepth = 0;

  void _declare(String name) {
    _scopes.last[name] = _Decl(_scopes.length - 1, _loopDepth > 0);
  }

  _Decl? _resolve(String name) {
    for (var i = _scopes.length - 1; i >= 0; i--) {
      final decl = _scopes[i][name];
      if (decl != null) {
        return decl;
      }
    }
    return null;
  }

  void _scoped(void Function() fn) {
    _scopes.add({});
    fn();
    _scopes.removeLast();
  }

  void _declareParameters(FormalParameterList? parameters) {
    for (final p in parameters?.parameters ?? const <FormalParameter>[]) {
      final name = p.name?.lexeme;
      if (name != null) {
        _declare(name);
      }
    }
  }

  void _markWrite(Expression lhs) {
    if (lhs is! SimpleIdentifier) {
      // Writes through indexes or properties mutate a shared object rather
      // than a frame slot, so they remain visible with a copied frame
      return;
    }
    final decl = _resolve(lhs.name);
    if (decl == null) {
      return;
    }
    for (final c in _closures) {
      if (decl.scopeIndex < c.baseScope) {
        c.writesCapturedVariable = true;
      }
    }
  }

  void _visitLoop(ForLoopParts parts, AstNode body) {
    if (parts is ForEachParts) {
      parts.iterable.accept(this);
    }
    _scopes.add({});
    _loopDepth++;
    if (parts is ForEachPartsWithDeclaration) {
      _declare(parts.loopVariable.name.lexeme);
    } else if (parts is ForEachPartsWithIdentifier) {
      parts.identifier.accept(this);
    } else if (parts is ForPartsWithDeclarations) {
      parts.variables.accept(this);
    } else if (parts is ForPartsWithExpression) {
      parts.initialization?.accept(this);
    }
    if (parts is ForParts) {
      parts.condition?.accept(this);
      for (final u in parts.updaters) {
        u.accept(this);
      }
    }
    body.accept(this);
    _loopDepth--;
    _scopes.removeLast();
  }

  @override
  void visitBlock(Block node) {
    _scoped(() => node.visitChildren(this));
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    node.initializer?.accept(this);
    _declare(node.name.lexeme);
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    _declare(node.functionDeclaration.name.lexeme);
    super.visitFunctionDeclarationStatement(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _scoped(() {
      _declareParameters(node.parameters);
      node.body.accept(this);
    });
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _scoped(() {
      _declareParameters(node.parameters);
      for (final i in node.initializers) {
        i.accept(this);
      }
      node.body.accept(this);
    });
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _scopes.add({});
    _declareParameters(node.parameters);
    final closure = _Closure(node.offset, _scopes.length - 1);
    _closures.add(closure);
    node.body.accept(this);
    _closures.removeLast();
    _scopes.removeLast();
    if (_loopDepth > 0 &&
        closure.capturesLoopVariable &&
        !closure.writesCapturedVariable) {
      result.add(node.offset);
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.inDeclarationContext()) {
      return;
    }
    final parent = node.parent;
    if ((parent is PropertyAccess && parent.propertyName == node) ||
        (parent is PrefixedIdentifier && parent.identifier == node) ||
        (parent is MethodInvocation &&
            parent.methodName == node &&
            (parent.target != null || parent.isCascaded)) ||
        parent is Label ||
        parent is ConstructorName) {
      return;
    }
    final decl = _resolve(node.name);
    if (decl == null || !decl.inLoop) {
      return;
    }
    for (final c in _closures) {
      if (decl.scopeIndex < c.baseScope) {
        c.capturesLoopVariable = true;
      }
    }
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _markWrite(node.leftHandSide);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.operator.type == TokenType.PLUS_PLUS ||
        node.operator.type == TokenType.MINUS_MINUS) {
      _markWrite(node.operand);
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (node.operator.type == TokenType.PLUS_PLUS ||
        node.operator.type == TokenType.MINUS_MINUS) {
      _markWrite(node.operand);
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    node.condition.accept(this);
    _loopDepth++;
    node.body.accept(this);
    _loopDepth--;
  }

  @override
  void visitDoStatement(DoStatement node) {
    _loopDepth++;
    node.body.accept(this);
    _loopDepth--;
    node.condition.accept(this);
  }

  @override
  void visitForStatement(ForStatement node) {
    _visitLoop(node.forLoopParts, node.body);
  }

  @override
  void visitForElement(ForElement node) {
    _visitLoop(node.forLoopParts, node.body);
  }

  @override
  void visitCatchClause(CatchClause node) {
    _scoped(() {
      final exception = node.exceptionParameter?.name.lexeme;
      if (exception != null) {
        _declare(exception);
      }
      final stackTrace = node.stackTraceParameter?.name.lexeme;
      if (stackTrace != null) {
        _declare(stackTrace);
      }
      node.body.accept(this);
    });
  }
}
