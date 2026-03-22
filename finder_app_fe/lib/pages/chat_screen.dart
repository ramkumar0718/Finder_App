import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';
import 'package:open_filex/open_filex.dart';
import '../utils/string_extensions.dart';

class ChatScreen extends StatefulWidget {
  final String? conversationId;
  final String title;
  final String? targetUserId;
  final String? targetUserRole;
  final String? itemImage;
  final String? itemSubtitle;

  const ChatScreen({
    super.key,
    this.conversationId,
    required this.title,
    this.targetUserId,
    this.targetUserRole,
    this.itemImage,
    this.itemSubtitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final FocusNode _focusNode = FocusNode();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _showEmoji = false;
  String? _conversationId;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showEmoji = false;
        });
      }
    });
    _conversationId = widget.conversationId;
    _initChat();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    if (_conversationId == null && widget.targetUserId != null) {
      final conversation = await ApiService().createConversation(
        widget.targetUserId!,
      );
      if (!mounted) return;
      if (conversation != null) {
        setState(() {
          _conversationId = conversation.id;
        });
      }
    }

    if (!mounted) return;

    if (_conversationId != null) {
      await _fetchMessages();
      if (!mounted) return;
      _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) {
          _fetchMessages(silent: true);
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    if (_conversationId == null) return;

    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final msgs = await ApiService().fetchMessages(_conversationId!);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _isLoading = false;
        });
        if (!silent) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent,
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _fetchMessages(silent: true);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({File? file, String msgType = 'text'}) async {
    final text = _controller.text.trim();
    if ((text.isEmpty && file == null) || _conversationId == null) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _controller.clear();

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // Optimistic display message
    final tempMsg = Message(
      id: tempId,
      conversationId: _conversationId!,
      senderId: currentUserId,
      senderUser: ChatUser(userId: currentUserId, name: 'You'),
      content: text,
      msgType: msgType,
      fileUrl: file?.path,
      timestamp: DateTime.now(),
      isRead: false,
      isSending: true,
    );

    if (mounted) {
      setState(() {
        _messages.add(tempMsg);
        _showEmoji = false;
      });
    }
    _scrollToBottom();

    final newMessage = await ApiService().sendMessage(
      _conversationId!,
      text,
      msgType: msgType,
      file: file,
    );

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == tempId);
        if (index != -1) {
          if (newMessage != null) {
            _messages[index] = newMessage;
          } else {
            _messages.removeAt(index);
          }
        }
      });
      _scrollToBottom();
    }
  }

  void _onBackspacePressed() {
    _controller
      ..text = _controller.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
  }

  void _handleAttachment() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            height: 140,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachAction(
                  Icons.picture_as_pdf,
                  'Document',
                  Colors.orange,
                  () {
                    Navigator.pop(context);
                    _pickFile();
                  },
                ),
                _buildAttachAction(Icons.camera_alt, 'Camera', Colors.teal, () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                }),
                _buildAttachAction(Icons.image, 'Gallery', Colors.purple, () {
                  Navigator.pop(context);
                  _pickMultipleImages();
                }),
              ],
            ),
          ),
    );
  }

  Widget _buildAttachAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: CircleAvatar(
            radius: 28,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile != null) {
        _showFilePreview(File(pickedFile.path), 'image');
      }
    } catch (e) {
      // Error picking image
    }
  }

  Future<void> _pickMultipleImages() async {
    try {
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        final files = pickedFiles.map((xFile) => File(xFile.path)).toList();
        _showMultipleImagesPreview(files);
      }
    } catch (e) {
      // Error picking images
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        _showFilePreview(File(result.files.single.path!), 'file');
      }
    } catch (e) {
      // Error picking file
    }
  }

  void _showFilePreview(File file, String type) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Send ${type == 'image' ? 'Image' : 'File'}?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (type == 'image')
                  Image.file(file, height: 200, fit: BoxFit.cover)
                else
                  const Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Do you want to send this attachment?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _sendMessage(file: file, msgType: type);
                },
                child: const Text('Send'),
              ),
            ],
          ),
    );
  }

  void _showMultipleImagesPreview(List<File> files) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Send ${files.length} Images ?'),
            content: SizedBox(
              width: double.maxFinite,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(files[index], fit: BoxFit.cover),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  for (var file in files) {
                    await _sendMessage(file: file, msgType: 'image');
                    await Future.delayed(const Duration(milliseconds: 300));
                  }
                },
                child: const Text('Send All'),
              ),
            ],
          ),
    );
  }

  String _getAbsoluteUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('assets/')) return url;

    final cleanPath = url.startsWith('/') ? url : '/$url';

    const baseUrl = ApiService.baseDomain;
    return '$baseUrl$cleanPath';
  }

  void _showFullscreenImage(String imageUrl) {
    final absoluteUrl = _getAbsoluteUrl(imageUrl);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
                elevation: 0,
              ),
              body: Center(
                child: InteractiveViewer(
                  child: Image.network(
                    absoluteUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder:
                        (context, error, stackTrace) => const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white,
                            size: 50,
                          ),
                        ),
                  ),
                ),
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              widget.title.toTitleCase(),
              style: const TextStyle(color: Colors.white),
            ),
            if (widget.targetUserRole == 'admin') ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, size: 18, color: Colors.white),
            ],
          ],
        ),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                      onRefresh: _handleRefresh,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is UserScrollNotification) {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _showEmoji = false;
                            });
                          }
                          return true;
                        },
                        child: Builder(
                          builder: (context) {
                            final groupedMessages = _groupMessages(_messages);
                            return ListView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              itemCount: groupedMessages.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return _buildItemContext();
                                }
                                final msg = groupedMessages[index - 1];
                                final isMe =
                                    (msg is Message)
                                        ? msg.senderId == currentUserId
                                        : (msg as List<Message>)
                                                .first
                                                .senderId ==
                                            currentUserId;

                                bool showDateHeader = false;
                                DateTime msgDate =
                                    (msg is Message)
                                        ? msg.timestamp
                                        : (msg as List<Message>)
                                            .first
                                            .timestamp;

                                if (index == 1) {
                                  showDateHeader = true;
                                } else {
                                  final prevItem = groupedMessages[index - 2];
                                  final prevDate =
                                      (prevItem is Message)
                                          ? prevItem.timestamp.toLocal()
                                          : (prevItem as List<Message>)
                                              .first
                                              .timestamp
                                              .toLocal();
                                  final currDate = msgDate.toLocal();
                                  if (prevDate.day != currDate.day ||
                                      prevDate.month != currDate.month ||
                                      prevDate.year != currDate.year) {
                                    showDateHeader = true;
                                  }
                                }

                                return Column(
                                  children: [
                                    if (showDateHeader)
                                      _buildDateHeader(
                                        msg is Message
                                            ? msg.timestamp
                                            : msg[0].timestamp,
                                      ),
                                    if (msg is List<Message>)
                                      _buildImageGrid(msg, isMe)
                                    else
                                      _buildMessageBubble(msg as Message, isMe),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
          ),
          _buildInputArea(),
          if (_showEmoji)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                textEditingController: _controller,
                onBackspacePressed: _onBackspacePressed,
                config: const Config(
                  height: 256,
                  checkPlatformCompatibility: false,
                  emojiViewConfig: EmojiViewConfig(
                    columns: 7,
                    emojiSizeMax: 32,
                    verticalSpacing: 0,
                    horizontalSpacing: 0,
                    gridPadding: EdgeInsets.zero,
                    backgroundColor: Color(0xFFF2F2F2),
                    buttonMode: ButtonMode.MATERIAL,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    initCategory: Category.RECENT,
                    indicatorColor: Colors.blue,
                    iconColor: Colors.grey,
                    iconColorSelected: Colors.blue,
                    backspaceColor: Colors.blue,
                    categoryIcons: CategoryIcons(),
                  ),
                  skinToneConfig: SkinToneConfig(
                    enabled: true,
                    dialogBackgroundColor: Colors.white,
                    indicatorColor: Colors.grey,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );

    String text;
    if (dateToCheck == today) {
      text = 'Today';
    } else if (dateToCheck == yesterday) {
      text = 'Yesterday';
    } else {
      text = DateFormat('MMM d, yyyy').format(localDate);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildItemContext() {
    if (widget.itemImage == null && widget.itemSubtitle == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 20, top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          if (widget.itemImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _getAbsoluteUrl(widget.itemImage!),
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder:
                    (context, error, stackTrace) => Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image_not_supported, size: 20),
                    ),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chatting about',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueAccent.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  widget.itemSubtitle ?? 'This item',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message msg, bool isMe) {
    bool isImage = msg.msgType == 'image' && msg.fileUrl != null;
    if (!isImage && msg.fileUrl != null) {
      final url = msg.fileUrl!.toLowerCase();
      if (url.endsWith('.jpg') ||
          url.endsWith('.jpeg') ||
          url.endsWith('.png') ||
          url.endsWith('.webp')) {
        isImage = true;
      }
    }

    final bool isFile =
        !isImage && msg.msgType == 'file' && msg.fileUrl != null;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
        ),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF2979FF) : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: isMe ? const Radius.circular(20) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: isImage ? EdgeInsets.zero : const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isImage) ...[
                GestureDetector(
                  onTap:
                      () =>
                          msg.isSending
                              ? null
                              : _showFullscreenImage(msg.fileUrl!),
                  child: Stack(
                    children: [
                      msg.isSending
                          ? Image.file(
                            File(msg.fileUrl!),
                            width: 240,
                            height: 240,
                            fit: BoxFit.cover,
                          )
                          : Image.network(
                            _getAbsoluteUrl(msg.fileUrl!),
                            width: 240,
                            height: 240,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 240,
                                height: 240,
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image, size: 50),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 240,
                                height: 240,
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                          ),
                      if (msg.isSending)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black26,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                      if (!msg.isSending && msg.content.isEmpty)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat(
                                    'h:mm a',
                                  ).format(msg.timestamp.toLocal()),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.done_all,
                                    color: Colors.white,
                                    size: 13,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (msg.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          msg.content,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),

                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat(
                                'h:mm a',
                              ).format(msg.timestamp.toLocal()),
                              style: TextStyle(
                                color: isMe ? Colors.white70 : Colors.grey[600],
                                fontSize: 10,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.done_all,
                                color: isMe ? Colors.white70 : Colors.grey[600],
                                size: 13,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
              ] else if (isFile) ...[
                GestureDetector(
                  onTap: () => _openFile(msg.fileUrl!),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          isMe
                              ? Colors.white.withOpacity(0.1)
                              : Colors.white.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.red,
                          radius: 20,
                          child:
                              msg.isSending
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(
                                    Icons.picture_as_pdf,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.content.isNotEmpty
                                    ? msg.content
                                    : _getFileName(msg.fileUrl!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              if (msg.isSending ||
                                  _getFileSize(msg.fileUrl!) != null)
                                Text(
                                  msg.isSending
                                      ? 'Sending...'
                                      : _getFileSize(msg.fileUrl!)!,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!msg.isSending) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        DateFormat('h:mm a').format(msg.timestamp.toLocal()),
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.done_all,
                          color: Colors.white,
                          size: 13,
                        ),
                      ],
                    ],
                  ),
                ],
              ] else ...[
                // Normal Text
                if (msg.content.isNotEmpty)
                  Text(
                    msg.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                if (!msg.isSending) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        DateFormat('h:mm a').format(msg.timestamp.toLocal()),
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.done_all,
                          color: Colors.white,
                          size: 13,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    if (widget.targetUserRole == 'deleted') {
      return Container(
        padding: const EdgeInsets.all(20),
        color: Colors.grey[100],
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
              const SizedBox(width: 8),
              Text(
                'This account has been deleted.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.emoji_emotions_outlined,
                        color: _showEmoji ? Colors.blue : Colors.grey[600],
                      ),
                      onPressed: () {
                        setState(() {
                          _showEmoji = !_showEmoji;
                        });
                        if (_showEmoji) {
                          FocusScope.of(context).unfocus();
                        } else {
                          FocusScope.of(context).requestFocus(_focusNode);
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textCapitalization: TextCapitalization.none,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.attach_file, color: Colors.grey[600]),
                      onPressed: _handleAttachment,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(Icons.camera_alt, color: Colors.grey[600]),
                      onPressed: () => _pickImage(ImageSource.camera),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFF2979FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> _groupMessages(List<Message> messages) {
    if (messages.isEmpty) return [];
    List<dynamic> grouped = [];
    int i = 0;
    while (i < messages.length) {
      final current = messages[i];
      if (current.msgType == 'image' && current.fileUrl != null) {
        List<Message> cluster = [current];
        int j = i + 1;
        while (j < messages.length) {
          final next = messages[j];
          if (next.msgType == 'image' &&
              next.fileUrl != null &&
              next.senderId == current.senderId) {
            final currentDate = current.timestamp.toLocal();
            final nextDate = next.timestamp.toLocal();
            if (currentDate.year == nextDate.year &&
                currentDate.month == nextDate.month &&
                currentDate.day == nextDate.day) {
              cluster.add(next);
              j++;
            } else {
              break;
            }
          } else {
            break;
          }
        }
        if (cluster.isNotEmpty) {
          grouped.add(cluster);
          i = j;
        }
      } else {
        grouped.add(current);
        i++;
      }
    }
    return grouped;
  }

  Widget _buildImageGrid(List<Message> messages, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Wrap(
          alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
          spacing: 4,
          runSpacing: 4,
          children:
              messages.map((msg) {
                return GestureDetector(
                  onTap:
                      () =>
                          msg.isSending
                              ? null
                              : _showFullscreenImage(msg.fileUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 130,
                      height: 130,
                      child: Stack(
                        children: [
                          msg.isSending
                              ? Image.file(
                                File(msg.fileUrl!),
                                width: 130,
                                height: 130,
                                fit: BoxFit.cover,
                              )
                              : Image.network(
                                _getAbsoluteUrl(msg.fileUrl!),
                                width: 130,
                                height: 130,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, _, __) => Container(
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.broken_image),
                                    ),
                                loadingBuilder: (
                                  context,
                                  child,
                                  loadingProgress,
                                ) {
                                  if (loadingProgress == null) return child;
                                  return Container(color: Colors.grey[200]);
                                },
                              ),
                          if (msg.isSending)
                            Container(
                              color: Colors.black26,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),

                          if (!msg.isSending)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      DateFormat(
                                        'h:mm a',
                                      ).format(msg.timestamp.toLocal()),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 2),
                                      const Icon(
                                        Icons.done_all,
                                        color: Colors.white,
                                        size: 11,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  String _getFileName(String url) {
    try {
      final segments = Uri.parse(url).pathSegments;
      return segments.isNotEmpty ? segments.last : 'Document';
    } catch (e) {
      return 'Document.pdf';
    }
  }

  String? _getFileSize(String url) {
    if (!url.startsWith('http')) {
      try {
        final file = File(url);
        if (file.existsSync()) {
          final sizeInBytes = file.lengthSync();
          final sizeInMb = sizeInBytes / (1024 * 1024);
          if (sizeInMb < 1) {
            final sizeInKb = sizeInBytes / 1024;
            return '${sizeInKb.toStringAsFixed(0)} KB';
          }
          return '${sizeInMb.toStringAsFixed(1)} MB';
        }
      } catch (e) {
        // Error getting file size
      }
    }
    return null;
  }

  Future<void> _openFile(String url) async {
    if (url.isEmpty) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening file...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      String filePath;

      if (url.startsWith('http')) {
        filePath = await ApiService().downloadFile(url);
      } else if (url.startsWith('/')) {
        if (url.startsWith('/data/') ||
            url.startsWith('/storage/') ||
            url.startsWith('/var/')) {
          filePath = url;
        } else {
          final absoluteUrl = _getAbsoluteUrl(url);
          return _openFile(absoluteUrl);
        }
      } else {
        throw Exception('Invalid file URL/path');
      }

      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
