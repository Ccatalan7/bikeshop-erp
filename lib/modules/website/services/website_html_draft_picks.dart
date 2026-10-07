import 'website_html_draft_picks_stub.dart'
    if (dart.library.js_interop) 'website_html_draft_picks_web.dart';

/// What the page of the editor's «Vista HTML» tells the editor: through the
/// web view's handlers on the desktop and the phone, or, on the ERP on the
/// web, where the page is a frame, as messages signed with the view's nonce
/// ([websiteHtmlDraftPicks]).
sealed class WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftMessage();

  /// The message a handler's [name] and [arguments] carry, or `null` for
  /// one the editor does not know.
  static WebsiteHtmlDraftMessage? fromHandler(
    String name,
    List<dynamic> arguments,
  ) {
    Object? at(int index) => index < arguments.length ? arguments[index] : null;
    return fromPost(switch (name) {
      'vbDraftPick' => {'type': 'vb-draft-pick', 'id': at(0)},
      'vbDraftAction' => {
          'type': 'vb-draft-action',
          'id': at(0),
          'action': at(1),
        },
      'vbDraftEdit' => {
          'type': 'vb-draft-edit',
          'id': at(0),
          'field': at(1),
          'phase': at(2),
          'text': at(3),
          'token': at(4),
          'formatting': at(5),
        },
      'vbDraftSlide' => {'type': 'vb-draft-slide', 'id': at(0), 'index': at(1)},
      'vbDraftMove' => {
          'type': 'vb-draft-move',
          'id': at(0),
          'anchor': at(1),
          'side': at(2),
        },
      'vbDraftHeight' => {
          'type': 'vb-draft-height',
          'id': at(0),
          'phase': at(1),
          'value': at(2),
        },
      _ => const <String, Object?>{},
    });
  }

  /// The message a frame posted (`{type, id, …, nonce}`, already checked
  /// against the view's nonce), or a handler's as the same map.
  static WebsiteHtmlDraftMessage? fromPost(Map<dynamic, dynamic> data) {
    String? text(String key) => switch (data[key]) {
          final String value when value.isNotEmpty => value,
          _ => null,
        };
    final id = text('id');
    switch (data['type']) {
      case 'vb-draft-ready':
        return const WebsiteHtmlDraftReady();
      case 'vb-draft-result':
        if (data['call'] != 'vbDraftPicked') return null;
        return WebsiteHtmlDraftShown(data['result'] == true);
      case 'vb-draft-pick':
        return WebsiteHtmlDraftPick(id);
      case 'vb-draft-action':
        final action = text('action');
        if (id == null || action == null) return null;
        return WebsiteHtmlDraftAction(id, action);
      case 'vb-draft-edit':
        final field = text('field');
        final parsed =
            field == null ? null : WebsiteHtmlDraftTextField.parse(field);
        final step = switch (data['phase']) {
          'begin' => WebsiteHtmlDraftEditStep.begin,
          'commit' => WebsiteHtmlDraftEditStep.commit,
          'cancel' => WebsiteHtmlDraftEditStep.cancel,
          _ => null,
        };
        final written = data['text'] is String ? data['text'] as String : null;
        if (id == null || parsed == null || step == null) return null;
        if (step == WebsiteHtmlDraftEditStep.commit && written == null) {
          return null;
        }
        // Every edit carries the page's token: without one, an answer for
        // another edit could not be told from this one's.
        final token = text('token');
        if (token == null ||
            token.length > 64 ||
            !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(token)) {
          return null;
        }
        // What the page's toolbar changed: a few keys, each a value or
        // null; the editor applies them to the formatting it keeps.
        final rawFormatting = data['formatting'];
        final formatting = rawFormatting is Map
            ? <String, Object?>{
                for (final MapEntry(:key, :value) in rawFormatting.entries)
                  if (key is String &&
                      (value == null || value is bool || value is num))
                    key: value,
              }
            : null;
        if (rawFormatting is Map &&
            formatting!.length != rawFormatting.length) {
          return null;
        }
        return WebsiteHtmlDraftEdit(
          id,
          parsed,
          step,
          token,
          written,
          formatting,
        );
      case 'vb-draft-slide':
        final slide = switch (data['index']) {
          final num value when value >= 0 && value == value.roundToDouble() =>
            value.toInt(),
          _ => null,
        };
        if (id == null || slide == null) return null;
        return WebsiteHtmlDraftSlide(id, slide);
      case 'vb-draft-move':
        final anchor = text('anchor');
        final side = switch (data['side']) {
          'before' => WebsiteHtmlDraftSide.before,
          'after' => WebsiteHtmlDraftSide.after,
          _ => null,
        };
        if (id == null || anchor == null || side == null) return null;
        return WebsiteHtmlDraftMove(id, anchor, side);
      case 'vb-draft-height':
        final step = switch (data['phase']) {
          'begin' => WebsiteHtmlDraftHeightStep.begin,
          'commit' => WebsiteHtmlDraftHeightStep.commit,
          'cancel' => WebsiteHtmlDraftHeightStep.cancel,
          'reset' => WebsiteHtmlDraftHeightStep.reset,
          _ => null,
        };
        final value = switch (data['value']) {
          final num value when value.isFinite && value > 0 => value.toDouble(),
          _ => null,
        };
        if (id == null || step == null) return null;
        if (step == WebsiteHtmlDraftHeightStep.commit && value == null) {
          return null;
        }
        return WebsiteHtmlDraftHeight(id, step, value);
    }
    return null;
  }
}

/// The page, in a frame on the ERP on the web, is ready to be told things
/// ([websiteHtmlDraftTell]).
final class WebsiteHtmlDraftReady extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftReady();
}

/// Whether the page found the part `vbDraftPicked` named, told as a message
/// on the web.
final class WebsiteHtmlDraftShown extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftShown(this.found);

  final bool found;
}

/// A click on a part of the page ([id]), or on none (`null`).
final class WebsiteHtmlDraftPick extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftPick(this.id);

  final String? id;
}

/// A press on the picked block's bar.
final class WebsiteHtmlDraftAction extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftAction(this.id, this.action);

  final String id;
  final String action;
}

/// A carousel of the page turned to slide [index] with its arrows or dots.
final class WebsiteHtmlDraftSlide extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftSlide(this.id, this.index);

  final String id;
  final int index;
}

enum WebsiteHtmlDraftEditStep { begin, commit, cancel }

enum WebsiteHtmlDraftHeightStep { begin, commit, cancel, reset }

enum WebsiteHtmlDraftSide { before, after }

/// The picked block dragged in the page to the [side] of block [anchor].
final class WebsiteHtmlDraftMove extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftMove(this.id, this.anchor, this.side);

  final String id;
  final String anchor;
  final WebsiteHtmlDraftSide side;
}

/// The operator dragging the picked block's height handle: starting, done
/// at [value] CSS px (the canvas's logical px), leaving it, or asking for
/// the content's own height back.
final class WebsiteHtmlDraftHeight extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftHeight(this.id, this.step, [this.value]);

  final String id;
  final WebsiteHtmlDraftHeightStep step;
  final double? value;
}

/// The operator writing one of block [id]'s texts where it is drawn: asking
/// to start, done with [text], or leaving it as it was.
final class WebsiteHtmlDraftEdit extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftEdit(
    this.id,
    this.field,
    this.step,
    this.token, [
    this.text,
    this.formatting,
  ]);

  final String id;
  final WebsiteHtmlDraftTextField field;
  final WebsiteHtmlDraftEditStep step;
  final String? text;

  /// The page's name for this one edit: the answers carry it back, and a
  /// commit or cancel for another edit is not this one's.
  final String token;

  /// What the page's toolbar changed in the text's formatting, with a
  /// commit (`{bold: true, fontSize: 32}`); `null` when nothing.
  final Map<String, Object?>? formatting;
}

/// One text of a block as the store's HTML server marks it for the editor
/// (`data-edit-text`, `BlockRenderContext.editText`): the keys of its field
/// and, for an item of a list, the list's keys and the item's position —
/// the same field the Flutter canvas's `WebsiteInlineTextSlot` names.
class WebsiteHtmlDraftTextField {
  const WebsiteHtmlDraftTextField({
    required this.spec,
    required this.keys,
    this.collectionKeys = const [],
    this.index = 0,
  });

  /// `title`, `subtitle,description`, `question@items#2`: field keys, then
  /// `@` the list's keys and `#` the item's position. Anything else is not a
  /// field (`null`).
  static WebsiteHtmlDraftTextField? parse(String spec) {
    if (spec.length > 200) return null;
    final key = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
    List<String>? names(String raw) {
      final parts = raw.split(',');
      return parts.every(key.hasMatch) ? parts : null;
    }

    final at = spec.indexOf('@');
    if (at < 0) {
      final keys = names(spec);
      return keys == null
          ? null
          : WebsiteHtmlDraftTextField(spec: spec, keys: keys);
    }
    final hash = spec.indexOf('#', at);
    if (hash < 0) return null;
    final keys = names(spec.substring(0, at));
    final collection = names(spec.substring(at + 1, hash));
    final index = int.tryParse(spec.substring(hash + 1));
    if (keys == null || collection == null || index == null || index < 0) {
      return null;
    }
    return WebsiteHtmlDraftTextField(
      spec: spec,
      keys: keys,
      collectionKeys: collection,
      index: index,
    );
  }

  final String spec;
  final List<String> keys;
  final List<String> collectionKeys;
  final int index;
}

/// The page's messages signed with [nonce], the one the view gave its page:
/// a message from any other window is ignored. Empty on the other
/// platforms.
Stream<WebsiteHtmlDraftMessage> websiteHtmlDraftPicks(String nonce) =>
    websiteHtmlDraftPicksImpl(nonce);

/// Calls the page's [call] with [arguments] in the ERP on the web, where the
/// page is a frame of another origin: a message signed with [nonce] to the
/// page that said it is ready. `false` before then, and on other platforms.
bool websiteHtmlDraftTell(String nonce, String call, List<Object?> arguments) =>
    websiteHtmlDraftTellImpl(nonce, call, arguments);
