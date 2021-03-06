part of angular.core.dom_internal;

// This Directive is special and does not go through injection.
@NgDirective(selector: r':contains(/{{.*}}/)')
class NgTextMustacheDirective {
  final dom.Node _element;

  NgTextMustacheDirective(this._element,
                          String template,
                          Interpolate interpolate,
                          Scope scope,
                          FilterMap filters) {
    String expression = interpolate(template);

    scope.watch(expression,
                _updateMarkup,
                canChangeModel: false,
                filters: filters);
  }

  void _updateMarkup(text, previousText) {
    _element.text = text;
  }
}

// This Directive is special and does not go through injection.
@NgDirective(selector: r'[*=/{{.*}}/]')
class NgAttrMustacheDirective {
  bool _hasObservers;
  Watch _watch;
  NodeAttrs _attrs;
  String _attrName;

  // This Directive is special and does not go through injection.
  NgAttrMustacheDirective(this._attrs,
                          String template,
                          Interpolate interpolate,
                          Scope scope,
                          FilterMap filters) {
    var eqPos = template.indexOf('=');
    _attrName = template.substring(0, eqPos);
    String expression = interpolate(template.substring(eqPos + 1));

    _updateMarkup('', template);

    _attrs.listenObserverChanges(_attrName, (hasObservers) {
    if (_hasObservers != hasObservers) {
      _hasObservers = hasObservers;
      if (_watch != null) _watch.remove();
        _watch = scope.watch(expression, _updateMarkup, filters: filters,
            canChangeModel: _hasObservers);
      }
    });
  }

  void _updateMarkup(text, previousText) {
    if (text != previousText && !(previousText == null && text == '')) {
        _attrs[_attrName] = text;
    }
  }
}

