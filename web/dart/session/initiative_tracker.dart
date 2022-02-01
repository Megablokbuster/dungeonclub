import 'dart:async';
import 'dart:html';
import 'dart:math';

import 'package:dnd_interactive/actions.dart';

import '../../main.dart';
import '../communication.dart';
import '../font_awesome.dart';
import '../panels/panel_overlay.dart';
import 'character.dart';
import 'movable.dart';
import 'prefab.dart';

HtmlElement get initiativeBar => querySelector('#initiativeBar');
HtmlElement get charContainer => initiativeBar.querySelector('.roster');
InitiativeSummary _summary;

class InitiativeTracker {
  final rng = Random();

  bool _trackerActive = false;
  Timer diceAnim;
  Iterable<Movable> _similar;

  ButtonElement get callRollsButton => querySelector('#initiativeTracker');
  SpanElement get initiativeDice => querySelector('#initiativeDice');
  SpanElement get targetText => querySelector('#initiativeTarget');
  ButtonElement get userRollButton => querySelector('#initiativeRoll');
  ButtonElement get skipButton => querySelector('#initiativeSkip');
  ButtonElement get skipTypeButton => querySelector('#initiativeSkipType');
  HtmlElement get panel => querySelector('#initiativePanel');

  set showBar(bool v) => initiativeBar.classes.toggle('hidden', !v);
  set disabled(bool disabled) => callRollsButton.disabled = disabled;

  void init(bool isDM) {
    callRollsButton.onClick.listen((_) {
      _trackerActive = callRollsButton.classes.toggle('active');

      if (_trackerActive) {
        sendRollForInitiative();
      } else {
        outOfCombat();
        socket.sendAction(GAME_CLEAR_INITIATIVE);
      }
    });

    userRollButton.onClick.listen((_) => rollDice());
    skipButton.classes.toggle('hidden', !isDM);
    skipTypeButton.onClick.listen((_) => _rollForSimilar());
    if (isDM) {
      skipButton.onClick.listen((_) {
        _summary.mine.removeAt(0);
        nextRoll();
      });
    }
  }

  void sendRollForInitiative() {
    resetBar();
    socket.sendAction(GAME_ROLL_INITIATIVE);
    _summary.mine = user.session.board.movables.where((m) {
      var prefab = m.prefab;
      if (prefab is CharacterPrefab) {
        return !prefab.character.hasJoined;
      }
      if (prefab is CustomPrefab) {
        return prefab.accessIds.length != 1;
      }
      return true;
    }).toList();
    nextRoll();
  }

  void rollDice() {
    diceAnim?.cancel();
    var r = rng.nextInt(20) + 1;
    initiativeDice.text = '$r';

    var movable = _summary.mine.removeAt(0);
    var prefab = movable.prefab;
    var dmOnly = user.session.isDM &&
        (prefab is EmptyPrefab ||
            (prefab is CustomPrefab && prefab.accessIds.isEmpty));

    _summary.registerRoll(movable, r, dmOnly);
    socket.sendAction(
        GAME_ADD_INITIATIVE, {'id': movable.id, 'roll': r, 'dm': dmOnly});

    _disableButtons(true);

    Future.delayed(Duration(milliseconds: 500), () {
      nextRoll();
    });
  }

  void _disableButtons(bool v) {
    skipButton.disabled = userRollButton.disabled = skipTypeButton.disabled = v;
  }

  void addToInBar(Map<String, dynamic> json) {
    int id = json['id'];
    int total = json['roll'];
    int mod = json['mod'];
    bool dm = json['dm'] ?? false;
    for (var movable in user.session.board.movables) {
      if (id == movable.id) {
        return _summary.registerRoll(movable, total, dm, mod);
      }
    }
  }

  void showRollerPanel() {
    resetBar();
    nextRoll();
  }

  void nextRoll() {
    if (_summary.mine.isEmpty) {
      if (panel.classes.remove('show')) overlayVisible = false;
      return;
    }

    diceAnim?.cancel();

    var roll = -1;
    diceAnim = Timer.periodic(Duration(milliseconds: 50), (_) {
      int r;
      do {
        r = rng.nextInt(20) + 1;
      } while (r == roll);

      roll = r;
      initiativeDice.text = '$r';
    });

    var mv = _summary.mine.first;
    var name = mv.name;
    targetText.innerHtml = "<b>$name</b>'s Initiative";

    var prefab = mv.prefab;
    _similar = _summary.mine.where((other) {
      if (mv is EmptyMovable) {
        return other is EmptyMovable && mv.label == other.label;
      }
      return other.prefab == prefab;
    });

    skipTypeButton.childNodes[0].text =
        'Roll for ${_similar.length} Similar Creatures';
    skipTypeButton.classes.toggle('hidden', _similar.length < 3);

    if (panel.classes.add('show')) overlayVisible = true;
    _disableButtons(false);
  }

  void _rollForSimilar() {
    if (_similar != null) {
      rollDice();
      _summary.mine.removeWhere((m) => _similar.contains(m));
    }
  }

  void resetBar() {
    _summary = InitiativeSummary();
    charContainer.children.clear();
    showBar = true;
  }

  void outOfCombat() {
    showBar = false;
    if (panel.classes.remove('show')) overlayVisible = false;
  }

  void onPrefabNameUpdate(CustomPrefab p) {
    for (var m in p.movables) {
      onNameUpdate(m);
    }
  }

  void onNameUpdate(Movable m) {
    if (_summary != null) {
      for (var entry in _summary.entries) {
        if (entry.movable == m) {
          entry.nameText.text = m.name;
          return;
        }
      }
    }
  }

  void onRemove(Movable m) {
    if (_summary != null) {
      for (var entry in _summary.entries.toList()) {
        if (entry.movable == m) {
          return _summary.removeEntry(entry);
        }
      }
    }
  }

  void onUpdate(Map<String, dynamic> json) {
    int id = json['id'];
    int mod = json['mod'];
    for (var entry in _summary.entries) {
      if (entry.movable.id == id) {
        var prefab = entry.movable.prefab;
        if (prefab is CharacterPrefab) prefab.character.defaultModifier = mod;

        entry.modifier = mod;
        return _summary.sort();
      }
    }
  }

  void fromJson(Iterable jList) {
    callRollsButton.classes.toggle('active', jList != null);
    if (jList == null) {
      outOfCombat();
    } else {
      resetBar();
      for (var j in jList) {
        addToInBar(j);
      }
    }
  }
}

class InitiativeSummary {
  List<Movable> mine;
  List<InitiativeEntry> entries = [];

  InitiativeSummary() {
    mine = user.session.board.movables.where((m) {
      if (!m.accessible) return false;

      var prefab = m.prefab;
      if (prefab is CustomPrefab) {
        return prefab.accessIds.length == 1;
      }

      return true;
    }).toList();
  }

  void removeEntry(InitiativeEntry entry) {
    entry.e.remove();
    entries.remove(entry);
  }

  void registerRoll(Movable movable, int base, bool dmOnly, [int mod]) {
    var entry = InitiativeEntry(movable, base, dmOnly);
    if (mod != null) entry.modifier = mod;

    entries.add(entry);
    charContainer.append(entry.e);
    sort();
  }

  void sort() {
    for (var n = entries.length; n > 1; --n) {
      for (var i = 0; i < n - 1; ++i) {
        var a = entries[i];
        var b = entries[i + 1];

        if (a.total < b.total) {
          charContainer.insertBefore(b.e, a.e);

          entries[i] = b;
          entries[i + 1] = a;
        }
      }
    }
  }
}

class InitiativeEntry {
  final e = DivElement();
  final modText = SpanElement();
  final totalText = SpanElement();
  final nameText = SpanElement();
  final Movable movable;
  final int base;
  final bool dmOnly;

  bool get isChar => movable.prefab is CharacterPrefab;
  Character get char =>
      isChar ? (movable.prefab as CharacterPrefab).character : null;
  int get total => base + modifier;

  int _modifier;
  int get modifier => _modifier;
  set modifier(int modifier) {
    _modifier = modifier;
    modText.text = (modifier >= 0 ? '+$modifier' : '$modifier');
    totalText.text = '$total';

    char?.defaultModifier = modifier;
  }

  InitiativeEntry(this.movable, this.base, this.dmOnly) {
    int _bufferedModifier;

    var img = movable.prefab.img(cacheBreak: false);
    e
      ..className = 'char'
      ..append(SpanElement()
        ..className = 'step-input'
        ..append(icon('minus')..onClick.listen((_) => modifier--))
        ..append(modText)
        ..append(icon('plus')..onClick.listen((_) => modifier++)))
      ..append(DivElement()
        ..style.backgroundImage = 'url($img)'
        ..append(totalText))
      ..append(nameText..text = movable.name)
      ..onMouseEnter.listen((_) {
        movable.e.classes.add('hovered');
        _bufferedModifier = modifier;
      })
      ..onMouseLeave.listen((_) {
        movable.e.classes.remove('hovered');
        if (modifier != _bufferedModifier) {
          _summary.sort();
          sendUpdate();
        }
      });

    modifier = char?.defaultModifier ?? 0;
  }

  void sendUpdate() {
    socket.sendAction(GAME_UPDATE_INITIATIVE, {
      'id': movable.id,
      'mod': modifier,
      if (isChar) 'pc': char.id,
    });
  }
}
