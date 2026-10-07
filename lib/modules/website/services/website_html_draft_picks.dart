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
    String? at(int index) {
      if (index >= arguments.length) return null;
      final value = arguments[index];
      return value is String && value.isNotEmpty ? value : null;
    }

    return _read(
      kind: name,
      id: at(0),
      action: at(1),
      field: at(1),
      phase: at(2),
      text: arguments.length > 3 && arguments[3] is String
          ? arguments[3] as String
          : null,
    );
  }

  /// The message a frame posted (`{type, id, …, nonce}`), already checked
  /// against the view's nonce.
  static WebsiteHtmlDraftMessage? fromPost(Map<dynamic, dynamic> data) {
    String? text(String key) => switch (data[key]) {
          final String value when value.isNotEmpty => value,
          _ => null,
        };
    return _read(
      kind: switch (data['type']) {
        'vb-draft-pick' => 'vbDraftPick',
        'vb-draft-action' => 'vbDraftAction',
        'vb-draft-edit' => 'vbDraftEdit',
        _ => '',
      },
      id: text('id'),
      action: text('action'),
      field: text('field'),
      phase: text('phase'),
      text: data['text'] is String ? data['text'] as String : null,
    );
  }

  static WebsiteHtmlDraftMessage? _read({
    required String kind,
    required String? id,
    required String? action,
    required String? field,
    required String? phase,
    required String? text,
  }) {
    switch (kind) {
      case 'vbDraftPick':
        return WebsiteHtmlDraftPick(id);
      case 'vbDraftAction':
        if (id == null || action == null) return null;
        return WebsiteHtmlDraftAction(id, action);
      case 'vbDraftEdit':
        final parsed =
            field == null ? null : WebsiteHtmlDraftTextField.parse(field);
        final step = switch (phase) {
          'begin' => WebsiteHtmlDraftEditStep.begin,
          'commit' => WebsiteHtmlDraftEditStep.commit,
          'cancel' => WebsiteHtmlDraftEditStep.cancel,
          _ => null,
        };
        if (id == null || parsed == null || step == null) return null;
        if (step == WebsiteHtmlDraftEditStep.commit && text == null) {
          return null;
        }
        return WebsiteHtmlDraftEdit(id, parsed, step, text);
    }
    return null;
  }
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

enum WebsiteHtmlDraftEditStep { begin, commit, cancel }

/// The operator writing one of block [id]'s texts where it is drawn: asking
/// to start, done with [text], or leaving it as it was.
final class WebsiteHtmlDraftEdit extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftEdit(this.id, this.field, this.step, [this.text]);

  final String id;
  final WebsiteHtmlDraftTextField field;
  final WebsiteHtmlDraftEditStep step;
  final String? text;
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
