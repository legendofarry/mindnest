import 'package:flutter/material.dart';

class CrisisCounselorSupportScreen extends StatelessWidget {
  const CrisisCounselorSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        title: const Text(
          'Talk to a Counselor',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF071937),
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4F7FB), Color(0xFFEFF8F7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD6E4F2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0E9B90,
                              ).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFF0E9B90),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'UI Preview',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Counselors who opt into Immediate Crisis Support will appear here.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF5B6B82),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    itemCount: _previewCounselors.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final counselor = _previewCounselors[index];
                      return _CrisisCounselorCard(counselor: counselor);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CrisisCounselorCard extends StatelessWidget {
  const _CrisisCounselorCard({required this.counselor});

  final _PreviewCounselor counselor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E4F1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFFE8F8F6),
            child: Text(
              counselor.initials,
              style: const TextStyle(
                color: Color(0xFF0E9B90),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  counselor.name,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  counselor.note,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Crisis calling flow will be connected after counselor opt-in is added.',
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E9B90),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.ring_volume_rounded, size: 16),
            label: const Text(
              'Call',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCounselor {
  const _PreviewCounselor({
    required this.name,
    required this.initials,
    required this.note,
  });

  final String name;
  final String initials;
  final String note;
}

const _previewCounselors = <_PreviewCounselor>[
  _PreviewCounselor(
    name: 'Dr. Mercy Achieng',
    initials: 'MA',
    note: 'School counselor - crisis line preview',
  ),
  _PreviewCounselor(
    name: 'Peter Odhiambo',
    initials: 'PO',
    note: 'Student support counselor - crisis line preview',
  ),
  _PreviewCounselor(
    name: 'Esther Njeri',
    initials: 'EN',
    note: 'Mental wellness counselor - crisis line preview',
  ),
];
