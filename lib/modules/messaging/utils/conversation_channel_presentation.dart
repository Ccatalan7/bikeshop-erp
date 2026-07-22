import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/conversation.dart';

/// One restrained presentation contract for every employee messaging surface.
///
/// Keeping channel markers here prevents the routed inbox, quick panels and
/// embedded chat hosts from assigning different meanings to the same provider.
abstract final class ConversationChannelPresentation {
  static const Color whatsAppAccent = Color(0xFF047857);
  static const Color instagramAccent = Color(0xFF9A3F78);
  static const Color facebookMessengerAccent = Color(0xFF2563EB);
  static const Color websiteAccent = Color(0xFF0F4C81);
  static const Color internalAccent = Color(0xFF475569);
  static const Color pendingAccent = Color(0xFFD97706);

  static IconData icon(Conversation conversation) =>
      iconForChannel(conversation.channel);

  static IconData iconForChannel(String? channel) {
    return switch (channel?.trim().toLowerCase()) {
      'whatsapp' => Icons.phone_in_talk_outlined,
      'instagram' => Icons.photo_camera_outlined,
      'facebook_messenger' => Icons.forum_outlined,
      'website_portal' => Icons.language_outlined,
      'internal' => Icons.groups_outlined,
      _ => Icons.chat_bubble_outline,
    };
  }

  /// Recognizable provider glyphs for compact platform navigation and markers.
  static IconData platformIconForChannel(String? channel) {
    return switch (channel?.trim().toLowerCase()) {
      'whatsapp' => FontAwesomeIcons.whatsapp,
      'instagram' => FontAwesomeIcons.instagram,
      'facebook_messenger' => FontAwesomeIcons.facebookMessenger,
      'facebook' => FontAwesomeIcons.facebookF,
      'website_portal' => FontAwesomeIcons.globe,
      _ => iconForChannel(channel),
    };
  }

  static bool usesPlatformGlyph(String? channel) {
    return switch (channel?.trim().toLowerCase()) {
      'whatsapp' ||
      'instagram' ||
      'facebook_messenger' ||
      'facebook' ||
      'website_portal' =>
        true,
      _ => false,
    };
  }

  static Color accent(
    Conversation conversation, {
    bool isPending = false,
  }) {
    if (isPending) return pendingAccent;
    return accentForChannel(conversation.channel);
  }

  static Color accentForChannel(String? channel) {
    return switch (channel?.trim().toLowerCase()) {
      'whatsapp' => whatsAppAccent,
      'instagram' => instagramAccent,
      'facebook_messenger' => facebookMessengerAccent,
      'website_portal' => websiteAccent,
      _ => internalAccent,
    };
  }

  static String shortLabelForChannel(String? channel) {
    return switch (channel?.trim().toLowerCase()) {
      'whatsapp' => 'WhatsApp',
      'instagram' => 'Instagram',
      'facebook_messenger' => 'Messenger',
      'website_portal' => 'Web',
      'internal' => 'Interno',
      _ => 'Chat',
    };
  }
}
