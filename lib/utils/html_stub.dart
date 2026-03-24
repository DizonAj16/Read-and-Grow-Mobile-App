// Stub used on native (Android/iOS) — empty shells so the code compiles
class HtmlWindow {
  void open(String url, String target) {}
}
class HtmlAnchorElement {
  HtmlAnchorElement({String? href});
  void setAttribute(String k, String v) {}
  String target = '';
  void click() {}
  void remove() {}
}
class HtmlDocument {
  HtmlBody? get body => null;
}
class HtmlBody {
  void append(HtmlAnchorElement el) {}
}

final htmlWindow   = HtmlWindow();
final htmlDocument = HtmlDocument();