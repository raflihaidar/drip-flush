import 'package:flutter/material.dart';
import 'dart:async';

class PumpTimerWidget extends StatefulWidget {
  final Function()? onTimerComplete;
  final Color? primaryColor;
  
  const PumpTimerWidget({
    Key? key,
    this.onTimerComplete,
    this.primaryColor,
  }) : super(key: key);

  @override
  State<PumpTimerWidget> createState() => _PumpTimerWidgetState();
}

class _PumpTimerWidgetState extends State<PumpTimerWidget> {
  Timer? _timer;
  int _selectedMinutes = 0;
  int _selectedSeconds = 0;
  int _totalSeconds = 0;
  int _remainingSeconds = 0;
  bool _isRunning = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    if (_totalSeconds == 0) return;
    
    setState(() {
      _isRunning = true;
      _remainingSeconds = _totalSeconds;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _stopTimer();
          widget.onTimerComplete?.call();
        }
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = 0;
    });
  }

  void _setTime() {
    setState(() {
      _totalSeconds = (_selectedMinutes * 60) + _selectedSeconds;
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = widget.primaryColor ?? Theme.of(context).primaryColor;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 5,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer,
                color: primaryColor,
                size: 30,
              ),
              const SizedBox(width: 10),
              Text(
                'Timer Pompa',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          
          // Timer Display
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              _isRunning ? _formatTime(_remainingSeconds) : _formatTime(_totalSeconds),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 30),
          
          // Time Selector (only show when not running)
          if (!_isRunning) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Minutes selector
                Column(
                  children: [
                    const Text(
                      'Menit',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: primaryColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: _selectedMinutes > 0
                                ? () {
                                    setState(() {
                                      _selectedMinutes--;
                                      _setTime();
                                    });
                                  }
                                : null,
                          ),
                          Container(
                            width: 50,
                            alignment: Alignment.center,
                            child: Text(
                              _selectedMinutes.toString(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: _selectedMinutes < 59
                                ? () {
                                    setState(() {
                                      _selectedMinutes++;
                                      _setTime();
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                // Seconds selector
                Column(
                  children: [
                    const Text(
                      'Detik',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: primaryColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: _selectedSeconds > 0
                                ? () {
                                    setState(() {
                                      _selectedSeconds--;
                                      _setTime();
                                    });
                                  }
                                : null,
                          ),
                          Container(
                            width: 50,
                            alignment: Alignment.center,
                            child: Text(
                              _selectedSeconds.toString(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: _selectedSeconds < 59
                                ? () {
                                    setState(() {
                                      _selectedSeconds++;
                                      _setTime();
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
          
          // Control Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isRunning)
                ElevatedButton.icon(
                  onPressed: _totalSeconds > 0 ? _startTimer : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Mulai'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _stopTimer,
                  icon: const Icon(Icons.stop),
                  label: const Text('Berhenti'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),
          
          // Status indicator
          if (_isRunning) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.5),
                        spreadRadius: 2,
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Pompa sedang berjalan',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}