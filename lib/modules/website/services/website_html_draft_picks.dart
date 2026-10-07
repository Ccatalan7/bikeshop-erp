import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_image_fields.dart';

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
      'vbDraftLayerDrag' => {
          'type': 'vb-draft-layer-drag',
          'id': at(0),
          'slide': at(1),
          'layer': at(2),
          'phase': at(3),
          'mode': at(4),
          'values': at(5),
        },
      'vbDraftImage' => {
          'type': 'vb-draft-image',
          'id': at(0),
          'image': at(1),
        },
      'vbDraftLayer' => {
          'type': 'vb-draft-layer',
          'id': at(0),
          'slide': at(1),
          'layer': at(2),
        },
      'vbDraftLayerCommand' => {
          'type': 'vb-draft-layer-command',
          'id': at(0),
          'slide': at(1),
          'layer': at(2),
          'command': at(3),
        },
      'vbDraftButton' => {
          'type': 'vb-draft-button',
          'id': at(0),
          'button': at(1),
          'where': at(2),
        },
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
      case 'vb-draft-layer-drag':
        final layer = text('layer');
        final slide = switch (data['slide']) {
          final num value when value >= -1 && value == value.roundToDouble() =>
            value.toInt(),
          _ => null,
        };
        final step = switch (data['phase']) {
          'begin' => WebsiteHtmlDraftLayerDragStep.begin,
          'commit' => WebsiteHtmlDraftLayerDragStep.commit,
          'cancel' => WebsiteHtmlDraftLayerDragStep.cancel,
          _ => null,
        };
        final resize = switch (data['mode']) {
          'move' => false,
          'resize' => true,
          _ => null,
        };
        if (id == null ||
            slide == null ||
            step == null ||
            resize == null ||
            layer == null ||
            layer.length > 120 ||
            !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(layer)) {
          return null;
        }
        // A commit carries the layer's new place (x, y) or size (w, h), in
        // the canvas's units: those two keys only, each a finite number. A
        // place may be left of or above the canvas when the document lets
        // layers bleed; a size is never empty.
        Map<String, double>? values;
        if (step == WebsiteHtmlDraftLayerDragStep.commit) {
          final raw = data['values'];
          final keys = resize ? const ['w', 'h'] : const ['x', 'y'];
          if (raw is! Map ||
              raw.length != 2 ||
              !keys.every((key) => raw[key] is num)) {
            return null;
          }
          values = {
            for (final key in keys) key: (raw[key] as num).toDouble(),
          };
          if (values.values.any(
            (value) =>
                !value.isFinite ||
                value > 20000 ||
                (resize ? value <= 0 : value < -20000),
          )) {
            return null;
          }
        }
        return WebsiteHtmlDraftLayerDrag(
          id,
          slide < 0 ? null : slide,
          layer,
          step,
          resize: resize,
          values: values,
        );
      case 'vb-draft-image':
        final spec = text('image');
        final image = spec == null || spec.length > 40
            ? null
            : WebsiteImageFields.parse(spec);
        if (id == null || image == null) return null;
        return WebsiteHtmlDraftImage(id, image.fields, image.index);
      case 'vb-draft-layer':
        final layer = text('layer');
        // A slide's stored position, or -1 for a canvas block's own layers.
        final slide = switch (data['slide']) {
          final num value when value >= -1 && value == value.roundToDouble() =>
            value.toInt(),
          _ => null,
        };
        if (id == null ||
            slide == null ||
            layer == null ||
            layer.length > 120 ||
            !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(layer)) {
          return null;
        }
        return WebsiteHtmlDraftLayer(id, slide < 0 ? null : slide, layer);
      case 'vb-draft-layer-command':
        final place = WebsiteHtmlDraftMessage.fromPost({
          'type': 'vb-draft-layer',
          'id': data['id'],
          'slide': data['slide'],
          'layer': data['layer'],
        });
        final command = switch (data['command']) {
          'remove' => WebsiteHtmlDraftLayerCommandKind.remove,
          'duplicate' => WebsiteHtmlDraftLayerCommandKind.duplicate,
          _ => null,
        };
        if (place is! WebsiteHtmlDraftLayer || command == null) return null;
        return WebsiteHtmlDraftLayerCommand(
          place.id,
          place.slide,
          place.layer,
          command,
        );
      case 'vb-draft-button':
        final spec = text('button');
        final button = spec == null || spec.length > 40
            ? null
            : WebsiteButtonFields.parse(spec);
        // Where the button is, as fractions of the page's window: four
        // finite numbers, or nothing (the editor then places its card
        // itself).
        final raw = data['where'];
        final where = raw is List &&
                raw.length == 4 &&
                raw.every((value) => value is num && value.isFinite)
            ? [for (final value in raw) (value as num).toDouble()]
            : null;
        if (id == null || button == null) return null;
        return WebsiteHtmlDraftButton(
          id,
          button.fields,
          button.index,
          where == null
              ? null
              : (
                  left: where[0],
                  top: where[1],
                  width: where[2],
                  height: where[3]
                ),
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

enum WebsiteHtmlDraftLayerDragStep { begin, commit, cancel }

/// The operator dragging the picked canvas layer [layer] (of carousel slide
/// [slide], or of a canvas block's own canvas when `null`): starting, done
/// with its new place or size ([values], in the canvas's units), or leaving
/// it as it was.
final class WebsiteHtmlDraftLayerDrag extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftLayerDrag(
    this.id,
    this.slide,
    this.layer,
    this.step, {
    required this.resize,
    this.values,
  });

  final String id;
  final int? slide;
  final String layer;
  final WebsiteHtmlDraftLayerDragStep step;

  /// A resize from its corner grip (`w`, `h`), or a move (`x`, `y`).
  final bool resize;
  final Map<String, double>? values;
}

/// A click on one of the picked block's photos: its address to replace
/// ([fields], of the item stored at [index] for a photo of a list).
final class WebsiteHtmlDraftImage extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftImage(this.id, this.fields, this.index);

  final String id;
  final WebsiteImageFields fields;
  final int index;
}

/// A click on a canvas layer of the picked block: layer [layer] of carousel
/// slide [slide] (its stored position), or of a canvas block's own canvas
/// (`null`).
final class WebsiteHtmlDraftLayer extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftLayer(this.id, this.slide, this.layer);

  final String id;
  final int? slide;
  final String layer;
}

/// What a key does to the picked canvas layer, as on the canvas: Delete
/// removes it, ⌘D (Ctrl+D) duplicates it.
enum WebsiteHtmlDraftLayerCommandKind { remove, duplicate }

/// A key pressed in the page on the picked canvas layer of block [id] (of
/// carousel slide [slide], or the canvas block's own for `null`), for the
/// editor to remove or duplicate it.
final class WebsiteHtmlDraftLayerCommand extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftLayerCommand(
    this.id,
    this.slide,
    this.layer,
    this.command,
  );

  final String id;
  final int? slide;
  final String layer;
  final WebsiteHtmlDraftLayerCommandKind command;
}

/// Where [press] picks a layer of [block] (an editor block row): the
/// carousel slide and how many slides there are, or `slide: null` for a
/// canvas block's own canvas; `null` for a layer the block does not hold.
({int? slide, int count})? websiteHtmlDraftLayerPlace(
  Map<String, dynamic> block,
  WebsiteHtmlDraftLayer press,
) {
  final data = block['block_data'];
  if (data is! Map) return null;
  bool holds(Object? elements) =>
      elements is List &&
      elements.any((element) => element is Map && element['id'] == press.layer);
  switch ((block['block_type'] ?? block['type'] ?? '').toString()) {
    case 'carousel':
      // The slide's place in the stored list, as the page and the canvas's
      // commands address it: an entry that is not a slide keeps its place.
      final slides = data['slides'] is List ? data['slides'] as List : const [];
      final slide = press.slide;
      if (slide == null || slide >= slides.length) return null;
      final stored = slides[slide];
      if (stored is! Map || !holds(stored['elements'])) return null;
      return (slide: slide, count: slides.length);
    case 'canvas':
      if (press.slide != null || !holds(data['elements'])) return null;
      return (slide: null, count: 0);
  }
  return null;
}

/// A press on one of the picked block's buttons: its label, destination and
/// look to edit ([fields], of the item stored at [index] for a button of a
/// list), and where the page draws it, as fractions of its window.
final class WebsiteHtmlDraftButton extends WebsiteHtmlDraftMessage {
  const WebsiteHtmlDraftButton(this.id, this.fields, this.index, this.where);

  final String id;
  final WebsiteButtonFields fields;
  final int index;
  final ({double left, double top, double width, double height})? where;
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
