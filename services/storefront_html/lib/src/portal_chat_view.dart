part of 'portal_page_view.dart';

/// «Soporte» (`/cuenta/chats`, `/cuenta/chats/<id>`) as Flutter's
/// `CustomerChatHubPage` and `CustomerChatView` draw it, with the words and
/// rules of `customer_chat_words.dart`. The page fits the window under the
/// tabs, as Flutter's portal does for a page that scrolls itself: the list,
/// or the open conversation with its messages and the composer at the foot,
/// and beside it in wide the job it is about.

/// What the chat draws, read as the customer ([PublicReads.customerChats]).
class PortalChatData {
  const PortalChatData({
    required this.conversations,
    required this.messages,
    required this.more,
    required this.files,
    required this.open,
    required this.window,
    required this.userId,
  });

  final List<Map<String, dynamic>> conversations;

  /// The open conversation's latest [window] messages, oldest first.
  final List<Map<String, dynamic>> messages;

  /// Whether older messages exist.
  final bool more;

  /// A short link to each private file, by message id.
  final Map<String, String> files;

  /// The conversation open (`/cuenta/chats/<id>`), or null for the list.
  final String? open;
  final int window;

  /// The session's user: what the customer wrote is theirs.
  final String? userId;

  Map<String, dynamic>? get conversation {
    for (final row in conversations) {
      if (row['id'] == open) return row;
    }
    return null;
  }
}

/// How many messages a conversation opens with, and how many more each
/// «Cargar mensajes anteriores» adds (`historyPageSize`).
const portalChatPage = 50;

final _chatPath = RegExp(
  r'^/cuenta/chats/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
  caseSensitive: false,
);

/// The conversation `/cuenta/chats/<uuid>` opens, or null.
String? portalChatId(String path) =>
    _chatPath.firstMatch(path)?.group(1)?.toLowerCase();

Component _chatPage(PortalViewData data, _Sheets sheets) {
  final chat = data.chat!;
  final open = chat.open;
  final conversation = chat.conversation;
  final title = open == null || conversation == null
      ? customerChatTitle
      : CustomerConversationPresentation.of(
          conversation,
          currentUserId: chat.userId,
        ).title;
  // Only a job the customer can read is shown beside it: an invoice is not
  // theirs to read (`sales_invoices` lets in its own staff).
  Map<String, dynamic>? job;
  if (conversation != null && conversation['context_type'] == 'job') {
    for (final row in data.jobs) {
      if (row['id'] == conversation['context_id']) job = row;
    }
  }
  final jobSheet = job == null ? null : sheets.job(job);
  final asksChanges = chat.messages.any(
    (m) =>
        m['type'] == 'action_request' &&
        CustomerChatActionCard.of(_metadata(m)).canAskChanges,
  );
  return div(
    classes: 'pt pt-chatpage',
    attributes: {
      'data-portal': 'ready',
      'data-page': 'chats',
      'data-chat': ?open,
      'data-chat-window': '${chat.window}',
    },
    [
      _tabsNav(PortalPage.chats.path),
      div(
        classes: [
          'pt-col',
          'pt-chat-main',
          if (open != null) 'thread',
          if (job != null) 'side',
        ].join(' '),
        [
          div(classes: 'pt-chat-body', [
            if (open != null)
              a(
                classes: 'pt-back',
                href: PortalPage.chats.path,
                attributes: {'aria-label': 'Volver'},
                [RawText(materialIcon(mdArrowBack, size: 18)), _t('Volver')],
              ),
            div(classes: 'pt-chat-head', [
              h1(classes: 'pt-chat-title', [_t(title)]),
              if (open == null && chat.conversations.isNotEmpty)
                _button(
                  customerChatNew,
                  icon: mdAdd,
                  attributes: {'data-chat-new': ''},
                ),
            ]),
            if (open == null)
              p(classes: 'pt-chat-lead', [_t(customerChatLead)]),
            if (open == null)
              _chatList(chat)
            else
              _chatThread(chat, conversation, jobSheet),
          ]),
          if (job != null) _chatJobSide(job, jobSheet!),
        ],
      ),
      _chatNewDialog(),
      if (asksChanges) _chatChangesDialog(),
      ...sheets.built,
    ],
  );
}

// ================================================================ the list

Component _chatList(PortalChatData chat) {
  if (chat.conversations.isEmpty) {
    return div(classes: 'pt-chat-list', [
      _empty(
        customerChatEmptyTitle,
        message: customerChatEmptyBody,
        actions: [
          _button(
            customerChatNew,
            icon: mdAdd,
            attributes: {'data-chat-new': ''},
          ),
        ],
      ),
    ]);
  }
  return div(classes: 'pt-chat-list', [
    div(classes: 'pt-rows', [
      for (final conversation in chat.conversations)
        _conversationRow(conversation, chat.userId),
    ]),
  ]);
}

/// `_ConversationRow`: what it is about, the last message and when.
Component _conversationRow(Map<String, dynamic> conversation, String? me) {
  final view = CustomerConversationPresentation.of(
    conversation,
    currentUserId: me,
  );
  final when = view.lastActivity == null
      ? null
      : portalRelativeDay(view.lastActivity!);
  final icon = switch (conversation['context_type']?.toString()) {
    'invoice' => mdReceiptLongOutlined,
    'job' => mdBuildOutlined,
    _ => mdChatBubbleOutline,
  };
  final tag = view.statusLabel == null
      ? null
      : _tag(
          view.statusLabel!,
          view.tone == PortalTone.neutral ? 'quiet' : 'ink',
        );
  final preview = view.preview ?? customerChatNoMessages;
  return a(
    classes: 'pt-row pt-crow',
    href: '${PortalPage.chats.path}/${conversation['id']}',
    attributes: {
      'aria-label': [view.title, ?when].join(', '),
    },
    [
      div(classes: 'pt-crow-in', [
        _thumb(fallback: icon, size: 64),
        div(classes: 'pt-what', [
          p(classes: 'pt-row-title', [_t(view.title)]),
          p(classes: 'pt-row-meta pt-crow-meta', [
            _t(preview),
            if (when != null) span(classes: 'pt-crow-when', [_t(' · $when')]),
          ]),
          if (tag != null) div(classes: 'pt-crow-foot', [tag]),
        ]),
        div(classes: 'pt-crow-end', [
          if (when != null) p(classes: 'pt-row-meta', [_t(when)]),
          ?tag,
        ]),
        RawText(materialIcon(mdArrowForward, size: 18)),
      ]),
    ],
  );
}

// ============================================================== the thread

Component _chatThread(
  PortalChatData chat,
  Map<String, dynamic>? conversation,
  String? jobSheet,
) {
  final state = conversation == null
      ? CustomerChatState.unavailable
      : CustomerChatState.of(conversation['status']?.toString());
  return div(
    classes: 'pt-chat-frame',
    attributes: {'data-chat-frame': ''},
    [
      if (jobSheet != null)
        div(classes: 'pt-chat-info', [
          button(
            classes: 'pt-link',
            attributes: {'type': 'button', 'data-sheet': jobSheet},
            [
              span(classes: 'pt-link-in', [
                _t(customerChatDetails),
                RawText(materialIcon(mdArrowForward, size: 16)),
              ]),
            ],
          ),
        ]),
      div(
        attributes: {'data-chat-live': 'state'},
        [
          if (state.banner(
                rejectReason: conversation?['reject_reason']?.toString(),
              )
              case final text?)
            div(classes: 'pt-chat-banner ${state.name}', [
              span(classes: 'pt-chat-banner-dot', const []),
              p([_t(text)]),
            ]),
        ],
      ),
      div(
        classes: 'pt-chat-scroll',
        attributes: {
          'data-chat-scroll': '',
          'role': 'log',
          'aria-label': 'Mensajes',
          'tabindex': '0',
        },
        [
          div(
            classes: 'pt-chat-log',
            attributes: {'data-chat-live': 'log'},
            _timeline(chat),
          ),
        ],
      ),
      div(
        attributes: {'data-chat-live': 'compose'},
        [
          if (state.canWrite)
            Component.element(
              tag: 'form',
              classes: 'pt-chat-compose',
              attributes: {'data-chat-compose': '', 'novalidate': ''},
              children: [
                textarea(
                  classes: 'pt-chat-input',
                  attributes: {
                    'name': 'text',
                    'rows': '1',
                    'placeholder': state.hint,
                    'aria-label': state.hint,
                    'maxlength': '$customerChatMessageMaxLength',
                    'autocapitalize': 'sentences',
                  },
                  const [],
                ),
                button(
                  classes: 'pt-chat-send',
                  attributes: {
                    'type': 'submit',
                    'aria-label': customerChatSend,
                    'title': customerChatSend,
                  },
                  [RawText(materialIcon(mdArrowUpward, size: 22))],
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

Map<String, dynamic> _metadata(Map<String, dynamic> message) {
  final value = message['metadata'];
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

/// The messages with a line for each day, and at the top the way to older
/// ones or where the conversation starts.
List<Component> _timeline(PortalChatData chat) {
  final today = portalLocalTime(DateTime.now().toUtc());
  final items = <Component>[
    if (chat.more)
      div(classes: 'pt-chat-edge', [
        button(
          classes: 'pt-chat-older',
          attributes: {'type': 'button', 'data-chat-older': ''},
          [
            RawText(materialIcon(mdHistoryRounded, size: 17)),
            _t(customerChatOlder),
          ],
        ),
      ])
    else if (chat.messages.isNotEmpty)
      p(classes: 'pt-chat-edge start', [_t(customerChatStart)]),
  ];
  String? previous;
  for (final message in chat.messages) {
    final at = portalParseDate(message['created_at']);
    final local = at == null ? null : portalLocalTime(at);
    if (local != null) {
      final day = customerChatDay(local, today);
      if (day != previous) {
        items.add(
          div(classes: 'pt-chat-day', [
            span(classes: 'pt-chat-day-label', [_t(day.toUpperCase())]),
          ]),
        );
        previous = day;
      }
    }
    items.add(_message(message, chat, local));
  }
  return items;
}

Component _message(
  Map<String, dynamic> message,
  PortalChatData chat,
  DateTime? at,
) {
  final id = '${message['id']}';
  final metadata = _metadata(message);
  final type = message['type']?.toString();
  final time = at == null ? '' : customerChatTime(at);
  if (type == 'action_request') return _actionCard(id, message, metadata, time);
  final mine = chat.userId != null && message['sender_id'] == chat.userId;
  final content = (message['content'] ?? '').toString();
  final file = customerChatFilePath(metadata, chat.open ?? '') != null;
  return div(
    classes: mine ? 'pt-msg mine' : 'pt-msg',
    attributes: {
      'data-msg': id,
      'data-mine': mine ? '1' : '0',
      if (type == 'system') 'data-sys': '',
      if (metadata['client_message_id'] case final String client)
        'data-client': client,
    },
    [
      div(classes: 'pt-msg-b', [
        if (file)
          _chatFile(id, type, metadata, chat.files[id])
        else
          p(classes: 'pt-msg-text', [.text(content)]),
        span(classes: 'pt-msg-time', [_t(time)]),
      ]),
    ],
  );
}

/// A private file: the picture, or the document's name to open it.
Component _chatFile(
  String id,
  String? type,
  Map<String, dynamic> metadata,
  String? url,
) {
  final label = customerChatFileLabel(type, metadata);
  if (url == null || url.isEmpty) {
    return button(
      classes: 'pt-msg-file none',
      attributes: {'type': 'button', 'data-chat-retry': ''},
      [
        RawText(materialIcon(mdRefreshRounded, size: 18)),
        span([_t(customerChatFileUnavailable(label))]),
      ],
    );
  }
  if (customerChatFileIsImage(type, metadata)) {
    return button(
      classes: 'pt-msg-img',
      attributes: {'type': 'button', 'data-chat-file': id, 'aria-label': label},
      [
        img(src: url, alt: '', attributes: {'loading': 'lazy'}),
        span(
          classes: 'pt-msg-img-bad',
          attributes: {'hidden': ''},
          [_t(customerChatImageFailed)],
        ),
      ],
    );
  }
  return button(
    classes: 'pt-msg-file',
    attributes: {'type': 'button', 'data-chat-file': id},
    [
      RawText(materialIcon(mdDescriptionOutlined, size: 22)),
      span(classes: 'pt-msg-file-name', [_t(label)]),
      RawText(materialIcon(mdOpenInNew, size: 16)),
    ],
  );
}

/// `_buildActionRequestCard`: the store's request, its state and, while it
/// waits, the customer's answer.
Component _actionCard(
  String id,
  Map<String, dynamic> message,
  Map<String, dynamic> metadata,
  String time,
) {
  final card = CustomerChatActionCard.of(metadata);
  return div(
    classes: 'pt-ask',
    attributes: {'data-msg': id, 'data-mine': '0', 'data-ask': card.actionType},
    [
      div(classes: 'pt-ask-head', [
        p(classes: 'pt-ask-title', [_t(card.title)]),
        if (card.tag case (final label, final kind)) _tag(label, kind),
      ]),
      p(classes: 'pt-ask-text', [.text((message['content'] ?? '').toString())]),
      if (card.note != null) p(classes: 'pt-ask-note', [.text(card.note!)]),
      if (card.payNote != null) p(classes: 'pt-ask-pay', [_t(card.payNote!)]),
      if (card.answerable)
        div(classes: 'pt-ask-actions', [
          button(
            classes: 'pt-btn pri',
            attributes: {
              'type': 'button',
              'data-chat-answer': 'accepted',
              'data-ask-type': card.actionType,
            },
            [
              span(
                classes: 'pt-btn-spin',
                attributes: {'hidden': ''},
                [RawText(_spinner)],
              ),
              RawText(materialIcon(mdCheck, size: 18)),
              span(classes: 'pt-btn-label', [_t(card.buttonLabel)]),
            ],
          ),
          if (card.canAskChanges)
            _button(
              customerChatAskChanges,
              kind: 'sec',
              attributes: {
                'data-chat-answer': 'declined',
                'data-ask-type': card.actionType,
              },
            ),
        ]),
      span(classes: 'pt-msg-time', [_t(time)]),
    ],
  );
}

// ============================================================ the context

/// Beside the conversation in wide: the job it is about, from the portal's
/// own reads, and the way to its sheet.
Component _chatJobSide(Map<String, dynamic> job, String sheet) {
  final presentation = CustomerWorkshopPresentation.of(job);
  final number = (job['job_number'] ?? '').toString().trim();
  final received = CustomerWorkshopPresentation.receivedAt(job);
  final total = CustomerWorkshopPresentation.total(job);
  final request = CustomerWorkshopPresentation.requestSummary(job);
  return Component.element(
    tag: 'aside',
    classes: 'pt-chat-side',
    attributes: {'aria-label': 'El trabajo de esta conversación'},
    children: [
      span(classes: 'pt-sh-bar', const []),
      p(classes: 'pt-eyebrow', [
        _t(number.isEmpty ? 'Servicio' : 'Servicio $number'),
      ]),
      p(classes: 'pt-chat-side-title', [
        _t(CustomerWorkshopPresentation.bikeTitle(job)),
      ]),
      div(classes: 'pt-chat-side-tag', [
        _statusTag(
          presentation.label,
          presentation.tone,
          needsCustomer: presentation.needsCustomer,
          active: presentation.isActive,
        ),
      ]),
      _facts([
        ('Lo que pediste', request.isEmpty ? null : request),
        ('Ingresó', received == null ? null : portalDate(received)),
        ('Total', total == null ? null : ChileanUtils.formatCurrency(total)),
      ]),
      button(
        classes: 'pt-link',
        attributes: {'type': 'button', 'data-sheet': sheet},
        [
          span(classes: 'pt-link-in', [
            _t('Ver el trabajo'),
            RawText(materialIcon(mdArrowForward, size: 16)),
          ]),
        ],
      ),
    ],
  );
}

// ================================================================ dialogs

/// «Nueva consulta»: what the customer needs, sent as the first message
/// (`create_customer_support_request`).
Component _chatNewDialog() => _alert(
  'pt-chat-new',
  width: 512,
  step: 'new',
  form: 'chat-new',
  attributes: {'data-chat-new-dialog': ''},
  title: [_t(customerChatNew)],
  body: [
    p(classes: 'pt-alert-sub', [_t(customerChatNewLead)]),
    _field(
      'chat_message',
      customerChatNewHint,
      rows: 4,
      maxLength: customerChatMessageMaxLength,
      capitalize: 'sentences',
      classes: 'pt-chat-field',
    ),
  ],
  actions: [
    _button(customerChatCancel, kind: 'sec', attributes: {'data-close': ''}),
    _submit(customerChatSend),
  ],
);

/// «Solicitar cambios» to a quote: what to adjust, sent with the decision.
Component _chatChangesDialog() => _alert(
  'pt-chat-changes',
  width: 480,
  step: 'changes',
  form: 'chat-changes',
  attributes: {'data-chat-changes-dialog': ''},
  title: [_t(customerChatAskChanges)],
  body: [
    _field(
      'chat_note',
      customerChatAskChangesHint,
      rows: 3,
      maxLength: customerChatNoteMaxLength,
      capitalize: 'sentences',
      classes: 'pt-chat-field',
    ),
  ],
  actions: [
    _button(customerChatCancel, kind: 'sec', attributes: {'data-close': ''}),
    _submit(customerChatAskChangesSend),
  ],
);
