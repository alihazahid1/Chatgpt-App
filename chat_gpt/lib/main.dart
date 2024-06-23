import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const MyApp());
}

class ChatUtils {
  static String extractContainerName(String message) {
    List<String> words = message.split(' ');
    return words.isNotEmpty ? words[0] : '';
  }
}

class ChatHistory {
  final String topic;
  final List<ChatMessage> messages;

  ChatHistory({required this.topic, required this.messages});
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat GPT',
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          color: Colors.transparent,
          elevation: 0,
        ),
        primarySwatch: Colors.grey,
        fontFamily: 'Roboto',
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  final String apiKey = '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';
  final String apiUrl = 'https://api.openai.com/v1/chat/completions';
  bool _waitingForResponse = false;
  List<String> _userHistory = [];
  Map<String, List<ChatMessage>?> chatHistories = {};
  ScrollController _scrollController = ScrollController();
  stt.SpeechToText _speech = stt.SpeechToText();
  FlutterTts flutterTts = FlutterTts();
  bool isTextToSpeechEnabled = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        text: 'Welcome to Chat GPT!',
        isUser: false,
        userAvatar: 'assets/chatgpt-icon.png',
      ),
    );
    _scrollController = ScrollController();
    _initSpeechToText();
    _initTextToSpeech();
  }

  void _initSpeechToText() async {
    _speech = stt.SpeechToText();
    await [Permission.microphone, Permission.speech].request();
    _speech.initialize(
      onError: (error) => print('Error: $error'),
      onStatus: (status) => print('Status: $status'),
    );
  }

  void _initTextToSpeech() async {
    isTextToSpeechEnabled = await flutterTts.isLanguageAvailable("en-US");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat GPT'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              setState(() {
                _messages.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              _showHistoryDialog();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: <Widget>[
              Flexible(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8.0),
                  reverse: false,
                  itemBuilder: (_, int index) => _messages[index],
                  itemCount: _messages.length,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      spreadRadius: 2,
                      blurRadius: 3,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildTextComposer(),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildTextComposer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.mic_none),
            onPressed: () {
              if (!_waitingForResponse) {
                _startListening();
                _showListeningBottomSheet();
              }
            },
          ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25.0),
                color: Colors.grey[200],
              ),
              child: TextField(
                controller: _textController,
                onSubmitted:
                _waitingForResponse ? null : _handleSubmitted,
                enabled: !_waitingForResponse,
                decoration: const InputDecoration(
                  hintText: 'Send a message',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          IconButton(
            icon: _waitingForResponse
                ? const Icon(Icons.stop)
                : const Icon(Icons.send),
            onPressed: _waitingForResponse
                ? () {
              setState(() {
                _waitingForResponse = false;
                Navigator.of(context).pop();
              });
            }
                : () {
              if (!_waitingForResponse) {
                _handleSubmitted(_textController.text);
              }
            },
          ),
        ],
      ),
    );
  }
  void _showListeningBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        bool isBottomSheetVisible = true;
        void hideBottomSheet() {
          setState(() {
            isBottomSheetVisible = false;
            Navigator.of(context).pop();
          });
        }
        Future.delayed(const Duration(seconds: 4), () {
          if (isBottomSheetVisible) {
            hideBottomSheet();
          }
        });
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Listening...'),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: hideBottomSheet,
                child: const Text('Stop'),
              ),
            ],
          ),
        );
      },
    );
  }
  Future<void> _handleSubmitted(String text) async {
    if (_waitingForResponse) {
      return;
    }
    final userMessageKey = ValueKey<String>(text);
    setState(() {
      _waitingForResponse = true;
      _messages.add(
        ChatMessage(
          key: userMessageKey,
          text: text,
          isUser: true,
          userAvatar: 'assets/pngegg (13.png',
        ),
      );
    });
    String topic = ChatUtils.extractContainerName(text);
    if (!chatHistories.containsKey(topic)) {
      chatHistories[topic] = [];
    }
    try {
      List<ChatMessage> response = await _getResponse(text);
      _userHistory.add(text);
      _textController.clear();
      _messages.removeLast();
      _messages.addAll(response);
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      chatHistories[topic]?.addAll(response);
      if (isTextToSpeechEnabled) {
        _speakResponse(response.last.text);
      }
    } catch (e) {
      print('Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _waitingForResponse = false;
      });
    }
  }
  Future<List<ChatMessage>> _getResponse(String userMessage) async {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
    final body = {
      'model': 'gpt-3.5-turbo',
      'messages': [
        {'role': 'system', 'content': 'You are a helpful assistant.'},
        {'role': 'user', 'content': userMessage},
      ],
    };
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);
        Map<String, dynamic> message = data['choices'][0]['message'];
        List<ChatMessage> messages = [
          ChatMessage(
            key: ValueKey<String>(userMessage),
            text: userMessage,
            isUser: true,
            userAvatar: 'assets/pngegg (13.png',
          ),
          ChatMessage(
            key: ValueKey<String>(message['content']),
            text: message['content'],
            isUser: false,
            userAvatar: 'assets/chatgpt-icon.png',
          ),
        ];
        String topic = ChatUtils.extractContainerName(userMessage);
        if (chatHistories[topic] != null) {
          chatHistories[topic]?.addAll(messages);
        }
        return messages;
      } else {
        throw Exception('Failed to load response');
      }
    } catch (e) {
      print('Error in API request: $e');
      throw Exception('Failed to load response');
    }
  }
  Future<void> _startListening() async {
    if (_speech == null) {
      print('Speech recognition is not available on this device.');
      return;
    }

    await _speech.initialize(
      onError: (error) => print('Error: $error'),
      onStatus: (status) => print('Status: $status'),
    );

    if (!_speech.isAvailable) {
      print('Speech recognition is not available on this device.');
      return;
    }
    bool isListening = await _speech.listen(
      onResult: (result) {
        setState(() {
          _textController.text = result.recognizedWords;
        });
      },
      listenFor: const Duration(seconds: 5),
    );

    if (!isListening) {
      print('Failed to start speech recognition.');
      setState(() {
        _waitingForResponse = false;
      });
    } else {
      // Hide the bottom sheet after listening
      Navigator.of(context).pop();
    }
  }
  Future<void> _speakAlertMessage(String message) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1.0);
    await flutterTts.speak(message);
  }

  Future<void> _speakResponse(String response) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1.0);
    await flutterTts.speak(response);
  }

  void errorListener(String errorMsg) {
    print('Speech recognition error: $errorMsg');
  }

  void statusListener(String status) {
    print('Speech recognition status: $status');
  }

  void _showHistoryDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HistoryScreen(
          chatHistories: chatHistories,
          onChatSelected: _continueChat,
        ),
      ),
    );
  }

  void _continueChat(List<ChatMessage> chatHistory) {
    setState(() {
      for (final message in chatHistory) {
        if (!_messages.contains(message)) {
          _messages.add(message);
        }
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;
  final String userAvatar;
  final Key? key;

  const ChatMessage({
    this.key,
    required this.text,
    required this.isUser,
    required this.userAvatar,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        crossAxisAlignment:
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              CircleAvatar(
                child: Image.asset(
                  userAvatar,
                  width: 40,
                  height: 40,
                  cacheWidth: 80,
                  cacheHeight: 80,
                ),
              ),
              const SizedBox(width: 8.0),
              Text(
                isUser ? "User:" : "ChatGpt:",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 5.0),
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: isUser ? Colors.blue[100] : Colors.blue[200],
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        text, style: const TextStyle(fontSize: 16.0),),),],),],),),],),);}}
class HistoryScreen extends StatelessWidget {
  final Map<String, List<ChatMessage>?> chatHistories;
  final Function(List<ChatMessage>) onChatSelected;
  HistoryScreen({
    required this.chatHistories,
    required this.onChatSelected,});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Message History'),
      ),
      body: chatHistories.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("There are no chat histories yet.", style: TextStyle(fontSize: 30),),
            Image.asset('assets/pngegg (11).png', height: 70, width: 70,),],),)
          : Container(
        margin: EdgeInsets.all(8.0),
        child: ListView.builder(
          itemCount: chatHistories.length,
          itemBuilder: (context, index) {
            final topic = chatHistories.keys.elementAt(index);
            final chatHistory = chatHistories[topic]!;
            final userMessages =
            chatHistory.where((message) => message.isUser).toList();
            if (userMessages.isEmpty) {
              return Container();
            }
            final lastUserMessage = userMessages.last;
            final messagesToDisplay = userMessages.sublist(1);
            return Container(
              margin:     const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: ListTile(
                title: Text(lastUserMessage.text),
                onTap: () {
                  onChatSelected(messagesToDisplay);
                  Navigator.of(context).pop();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
