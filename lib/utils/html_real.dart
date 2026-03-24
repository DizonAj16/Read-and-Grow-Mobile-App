// Real implementation used on web only
import 'dart:html' as dart_html;

class HtmlWindow {
  void open(String url, String target) => dart_html.window.open(url, target);
}
class HtmlAnchorElement {
  final dart_html.AnchorElement _el;
  HtmlAnchorElement({String? href})
      : _el = dart_html.AnchorElement(href: href);
  void setAttribute(String k, String v) => _el.setAttribute(k, v);
  set target(String t) => _el.target = t;
  void click() => _el.click();
  void remove() => _el.remove();
}
class HtmlDocument {
  dart_html.HtmlDocument get _d => dart_html.document;
  HtmlBody get body => HtmlBody(_d.body!);
}
class HtmlBody {
  final dart_html.Element _el;
  HtmlBody(this._el);
  void append(HtmlAnchorElement el) => _el.append(el._el);
}

final htmlWindow   = HtmlWindow();
final htmlDocument = HtmlDocument();