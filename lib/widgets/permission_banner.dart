import 'package:flutter/material.dart';

class PermissionBanner extends StatelessWidget {
  final VoidCallback onRequestPermission;

  const PermissionBanner({super.key, required this.onRequestPermission});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Storage access required to scan PDFs on your device.',
              style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onRequestPermission,
            child: const Text('Grant Access'),
          ),
        ],
      ),
    );
  }
}
