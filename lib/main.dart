import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum MessageTypes {
  purchase,
  reminder,
}

void main() => runApp(const SpeechSampleApp());

class SpeechSampleApp extends StatefulWidget {
  const SpeechSampleApp({Key? key}) : super(key: key);

  @override
  State<SpeechSampleApp> createState() => _SpeechSampleAppState();
}

/// An example that demonstrates the basic functionality of the
/// SpeechToText plugin for using the speech recognition capability
/// of the underlying platform.
class _SpeechSampleAppState extends State<SpeechSampleApp> with TickerProviderStateMixin {
  bool _hasSpeech = false;
  bool _logEvents = false;
  bool _onDevice = false;
  final TextEditingController _pauseForController =
      TextEditingController(text: '5');
  final TextEditingController _listenForController =
      TextEditingController(text: '35');
  double level = 0.0;
  double minSoundLevel = 50000;
  double maxSoundLevel = -50000;
  String lastWords = '';
  String lastError = '';
  String lastStatus = '';
  String _currentLocaleId = '';
  List<LocaleName> _localeNames = [];
  final SpeechToText speech = SpeechToText();

  // animation for loading indicator that appears after speech recognition giving User time to cancel send, or change message type
  late AnimationController controller;
  
  // Message type
  MessageTypes messageType = MessageTypes.purchase;

  @override
  void initState() {
    controller = AnimationController(

      /// [AnimationController]s can be created with `vsync: this` because of [TickerProviderStateMixin].
      vsync: this,
      
      duration: const Duration(seconds: 8),
    )..addListener(() {
      setState(() {});
    });
    // controller.repeat();

    super.initState();
  }

  /// This initializes SpeechToText. That only has to be done
  /// once per application, though calling it again is harmless
  /// it also does nothing. The UX of the sample app ensures that
  /// it can only be called once.
  Future<void> initSpeechState() async {
    _logEvent('Initialize');
    try {
      var hasSpeech = await speech.initialize(
        onError: errorListener,
        onStatus: statusListener,
        debugLogging: _logEvents,
      );
      if (hasSpeech) {
        // Get the list of languages installed on the supporting platform so they
        // can be displayed in the UI for selection by the user.
        _localeNames = await speech.locales();

        var systemLocale = await speech.systemLocale();
        _currentLocaleId = systemLocale?.localeId ?? '';
      }
      if (!mounted) return;

      setState(() {
        _hasSpeech = hasSpeech;
      });
    } catch (e) {
      setState(() {
        lastError = 'Speech recognition failed: ${e.toString()}';
        _hasSpeech = false;
      });
    }
  }

  void stopProgressAnimation() {
    controller.stop();
    setState(() {});
  }

  void startProgressAnimation() {
    controller.forward(from: 0);
    setState(() {});
  }

  Future<http.Response> sendTelegramMessage(String message) {
    const String botId = '135480527:AAE02c_FoptWIqGplKEbW5A_cRu43xPSsjc';
    const telegramGroupIds = {
      MessageTypes.purchase: '-4224310244',
      MessageTypes.reminder: '-4272844606',
    };

    String? groupId = telegramGroupIds[messageType];

    return http.get(Uri.parse('https://api.telegram.org/bot$botId/sendMessage?chat_id=$groupId&text=$message'));
  }

  void updateMessageType(MessageTypes newMessageType) {
    setState(() {
      messageType = newMessageType;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Mémomarché'),
        ),
        body: Column(children: [

          // const HeaderWidget(),

          Column(
            children: <Widget>[

              // InitSpeechWidget(_hasSpeech, initSpeechState),
              
              SpeechControlWidget(
                _hasSpeech, 
                speech.isListening, 
                startListening, 
                stopListening, 
                cancelListening
              ),

              SessionOptionsWidget(
                _currentLocaleId,
                _switchLang,
                _localeNames,
                _logEvents,
                _switchLogging,
                _pauseForController,
                _listenForController,
                _onDevice,
                _switchOnDevice,
              ),

            ],
          ),
          Expanded(
            flex: 4,
            child: RecognitionResultsWidget(
              level: level,
              lastWords: lastWords, 
              hasSpeech: _hasSpeech,
              isListening: speech.isListening,
              startListening: startListening,
              initSpeechState: initSpeechState,
            ),
          ),

          // Expanded(
          //   flex: 1,
          //   child: ErrorWidget(lastError: lastError),
          // ),

          // SpeechStatusWidget(speech: speech),

          MessageTypeSelection(updateMessageType: updateMessageType, messageType: messageType),
          LinearProgressIndicator(
            minHeight: 24,
            value: controller.value,
            semanticsLabel: 'Linear progress indicator',
          ),
        ]),
      ),
    );
  }

  // This is called each time the users wants to start a new speech
  // recognition session
  void startListening() {
    _logEvent('start listening');
    print('-----------------start');
    lastWords = '';
    lastError = '';
    final pauseFor = int.tryParse(_pauseForController.text);
    final listenFor = int.tryParse(_listenForController.text);
    final options = SpeechListenOptions(
        onDevice: _onDevice,
        listenMode: ListenMode.confirmation,
        cancelOnError: true,
        partialResults: true,
        autoPunctuation: true,
        enableHapticFeedback: true);
    // Note that `listenFor` is the maximum, not the minimum, on some
    // systems recognition will be stopped before this value is reached.
    // Similarly `pauseFor` is a maximum not a minimum and may be ignored
    // on some devices.
    speech.listen(
      onResult: resultListener,
      listenFor: Duration(seconds: listenFor ?? 30),
      pauseFor: Duration(seconds: pauseFor ?? 3),
      localeId: _currentLocaleId,
      onSoundLevelChange: soundLevelListener,
      listenOptions: options,
    );
    setState(() {});
  }

  void stopListening() {
    _logEvent('stop');
    print('-----------------stop');
    speech.stop();
    setState(() {
      level = 0.0;
    });
  }

  void cancelListening() {
    _logEvent('cancel');
    speech.cancel();
    setState(() {
      level = 0.0;
    });
  }

  /// This callback is invoked each time new recognition results are
  /// available after `listen` is called.
  void resultListener(SpeechRecognitionResult result) {
    _logEvent('Result listener final: ${result.finalResult}, words: ${result.recognizedWords}');
    print('Result listener final: ${result.finalResult}, words: ${result.recognizedWords}');
    
    String listeningVsFinalResultAchievedIndicatorIcon = (result.finalResult) ? '✅' : '🦻';
    setState(() {
      lastWords = '${result.recognizedWords} $listeningVsFinalResultAchievedIndicatorIcon';
    });

    if(result.finalResult) {
      startProgressAnimation();

      // Wait for 8 seconds 
      // TODO: parametrize wait time, 
      // potentially expose in-app while tinkering for some weeks
      Future.delayed(const Duration(milliseconds: 8 * 1000), () {

        sendTelegramMessage(result.recognizedWords);
        stopProgressAnimation();

      });
    }
  }

  void soundLevelListener(double level) {
    minSoundLevel = min(minSoundLevel, level);
    maxSoundLevel = max(maxSoundLevel, level);
    // _logEvent('sound level $level: $minSoundLevel - $maxSoundLevel ');
    setState(() {
      this.level = level;
    });
  }

  void errorListener(SpeechRecognitionError error) {
    _logEvent(
        'Received error status: $error, listening: ${speech.isListening}');
    setState(() {
      lastError = '${error.errorMsg} - ${error.permanent}';
    });
  }

  void statusListener(String status) {
    _logEvent(
        'Received listener status: $status, listening: ${speech.isListening}');
    setState(() {
      lastStatus = status;
    });
  }

  void _switchLang(selectedVal) {
    setState(() {
      _currentLocaleId = selectedVal;
    });
    debugPrint(selectedVal);
  }

  void _logEvent(String eventDescription) {
    if (_logEvents) {
      var eventTime = DateTime.now().toIso8601String();
      debugPrint('$eventTime $eventDescription');
    }
  }

  void _switchLogging(bool? val) {
    setState(() {
      _logEvents = val ?? false;
    });
  }

  void _switchOnDevice(bool? val) {
    setState(() {
      _onDevice = val ?? false;
    });
  }
}

class MessageTypeSelection extends StatelessWidget {
  const MessageTypeSelection({
    super.key,
    required this.messageType,
    required this.updateMessageType,
  });

  final MessageTypes messageType;
  final void Function(MessageTypes) updateMessageType;

  final double iconSize = 48;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
      IconButton(
        isSelected: messageType == MessageTypes.purchase,
        iconSize: iconSize,
        onPressed: () {
          updateMessageType(MessageTypes.purchase);
        }, 
        icon: Icon(Icons.shopping_cart)
      ),
      IconButton(
        isSelected: messageType == MessageTypes.reminder,
        iconSize: iconSize,
        onPressed: () {
          updateMessageType(MessageTypes.reminder);
        }, 
        icon: Icon(Icons.psychology_alt)
      )
    ],);
  }
}

/// Displays the most recently recognized words and the sound level.
class RecognitionResultsWidget extends StatelessWidget {
  const RecognitionResultsWidget({
    Key? key,
    required this.level,
    required this.hasSpeech,
    required this.lastWords,
    required this.isListening,
    required this.startListening,
    required this.initSpeechState,
  }) : super(key: key);

  final double level;
  final bool hasSpeech;
  final String lastWords;
  final bool isListening;
  final void Function() startListening;
  final void Function() initSpeechState;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Recognized Words',
              style: TextStyle(fontSize: 22),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: <Widget>[
              Container(
                // color: Theme.of(context).secondaryHeaderColor,
                color: Colors.black.withOpacity(.06),
                child: Center(
                  child: Text(
                    lastWords,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24),
                  ),
                ),
              ),
              Positioned.fill(
                bottom: 10,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                            blurRadius: .40,
                            spreadRadius: level * 1.5,
                            color: Colors.black.withOpacity(.04))
                      ],
                      color: Colors.white,
                      borderRadius: const BorderRadius.all(Radius.circular(99)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.mic),
                      onPressed: () {
                        hasSpeech ? null : initSpeechState();

                        Future.delayed(const Duration(milliseconds: 1 * 1000), () {
                          !hasSpeech || isListening ? null : startListening();
                        });
                      }
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HeaderWidget extends StatelessWidget {
  const HeaderWidget({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Speech recognition available',
        style: TextStyle(fontSize: 22.0),
      ),
    );
  }
}

/// Display the current error status from the speech
/// recognizer
class ErrorWidget extends StatelessWidget {
  const ErrorWidget({
    Key? key,
    required this.lastError,
  }) : super(key: key);

  final String lastError;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Center(
          child: Text((lastError != '') ? 'Error Statuss $lastError' : ''),
        ),
      ],
    );
  }
}

/// Controls to start and stop speech recognition
class SpeechControlWidget extends StatelessWidget {
  const SpeechControlWidget(
      this.hasSpeech, 
      this.isListening,
      this.stopListening, 
      this.startListening, 
      this.cancelListening,
      {Key? key}
    ) : super(key: key);

  final bool hasSpeech;
  final bool isListening;
  final void Function() startListening;
  final void Function() stopListening;
  final void Function() cancelListening;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        TextButton(
          onPressed: !hasSpeech || isListening ? null : startListening,
          child: const Text('Start'),
        ),
        TextButton(
          onPressed: isListening ? stopListening : null,
          child: const Text('Stop'),
        ),
        TextButton(
          onPressed: isListening ? cancelListening : null,
          child: const Text('Cancel'),
        )
      ],
    );
  }
}

class SessionOptionsWidget extends StatelessWidget {
  const SessionOptionsWidget(
      this.currentLocaleId,
      this.switchLang,
      this.localeNames,
      this.logEvents,
      this.switchLogging,
      this.pauseForController,
      this.listenForController,
      this.onDevice,
      this.switchOnDevice,
      {Key? key})
      : super(key: key);

  final String currentLocaleId;
  final void Function(String?) switchLang;
  final void Function(bool?) switchLogging;
  final void Function(bool?) switchOnDevice;
  final TextEditingController pauseForController;
  final TextEditingController listenForController;
  final List<LocaleName> localeNames;
  final bool logEvents;
  final bool onDevice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: [
              const Text('Language: '),
              DropdownButton<String>(
                onChanged: (selectedVal) => switchLang(selectedVal),
                value: currentLocaleId,
                items: localeNames
                    .map(
                      (localeName) => DropdownMenuItem(
                        value: localeName.localeId,
                        child: Text(localeName.name),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          Row(
            children: [
              const Text('pauseFor: '),
              Container(
                  padding: const EdgeInsets.only(left: 8),
                  width: 80,
                  child: TextFormField(
                    controller: pauseForController,
                  )),
              Container(
                  padding: const EdgeInsets.only(left: 16),
                  child: const Text('listenFor: ')),
              Container(
                  padding: const EdgeInsets.only(left: 8),
                  width: 80,
                  child: TextFormField(
                    controller: listenForController,
                  )),
            ],
          ),
          // Row(
          //   children: [
          //     const Text('On device: '),
          //     Checkbox(
          //       value: onDevice,
          //       onChanged: switchOnDevice,
          //     ),
          //     const Text('Log events: '),
          //     Checkbox(
          //       value: logEvents,
          //       onChanged: switchLogging,
          //     ),
          //   ],
          // ),
        ],
      ),
    );
  }
}

class InitSpeechWidget extends StatelessWidget {
  const InitSpeechWidget(this.hasSpeech, this.initSpeechState, {Key? key})
      : super(key: key);

  final bool hasSpeech;
  final Future<void> Function() initSpeechState;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        TextButton(
          onPressed: hasSpeech ? null : initSpeechState,
          child: const Text('Initialize'),
        ),
      ],
    );
  }
}

/// Display the current status of the listener
class SpeechStatusWidget extends StatelessWidget {
  const SpeechStatusWidget({
    Key? key,
    required this.speech,
  }) : super(key: key);

  final SpeechToText speech;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      color: Theme.of(context).colorScheme.background,
      child: Center(
        child: speech.isListening
            ? const Text(
                "I'm listening...",
                style: TextStyle(fontWeight: FontWeight.bold),
              )
            : const Text(
                'Not listening',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}

