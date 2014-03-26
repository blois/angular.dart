library dirty_checking_change_detector_dynamic;

import 'package:angular/change_detection/change_detection.dart';

/**
 * We are using mirrors, but there is no need to import anything.
 */
@MirrorsUsed(targets: const [], metaTargets: const [])
import 'dart:mirrors';

class DynamicFieldGetterFactory implements FieldGetterFactory {
  FieldGetter call (Object object, String name) {
    Symbol symbol = new Symbol(name);
    InstanceMirror instanceMirror = reflect(object);
    // Work around dartbug.com/17831 where getField on methods is not working
    // in dart2js- if the member is a method then wrap it with a method closure.
    var declaration = _findDeclaration(instanceMirror.type, symbol);
    if (declaration is MethodMirror) {
      return (Object object) {
        return new _MethodClosure(instanceMirror, symbol);
      };
    }
    return (Object object) {
      return instanceMirror.getField(symbol).reflectee;
    };
  }
}

DeclarationMirror _findDeclaration(ClassMirror cls, Symbol declarationName) {
  var decl = cls.declarations[declarationName];
  if (decl != null) {
    return decl;
  }
  if (cls.superclass != null) {
    return _findDeclaration(cls.superclass, declarationName);
  }
  return null;
}

// Helper for workaround for bug dartbug/17831- maps an instance method to a
// Function.
class _MethodClosure implements Function {
  final InstanceMirror instance;
  final Symbol symbol;
  _MethodClosure(this.instance, this.symbol);

  // Should never be called- should always go through noSuchMethod.
  call(some, large, number, of, args, that, should, never, be, encountered,
      ever) {}

  noSuchMethod(Invocation invocation) => instance.invoke(symbol,
      invocation.positionalArguments, invocation.namedArguments).reflectee;
}

