import 'dart:html';
import 'dart:math';

class Board {
  final HtmlElement e = querySelector('#board');
  final HtmlElement container = querySelector('#boardContainer');
  final ImageElement ground = querySelector('#board #ground');

  Point<num> _position;
  Point<num> get position => _position;
  set position(Point<num> pos) {
    _position = pos;
    _transform();
  }

  double _zoom = 0;
  double _scaledZoom = 1;
  double get zoom => _zoom;
  set zoom(double zoom) {
    _zoom = zoom;
    _scaledZoom = exp(zoom);
    _transform();
  }

  void _transform() {
    e.style.transform =
        'scale($_scaledZoom) translate(${position.x}px, ${position.y}px)';
  }

  Board() {
    position = Point(0, 0);

    var drag = false;
    container.onMouseDown.listen((event) async {
      drag = true;
      await window.onMouseUp.first;
      drag = false;
    });
    window.onMouseMove.listen((event) {
      if (drag) {
        position += event.movement * (1 / _scaledZoom);
      }
    });

    container.onMouseWheel.listen((event) {
      zoom -= event.deltaY / 300;
    });
  }
}