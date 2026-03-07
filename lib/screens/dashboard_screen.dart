import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/classroom.dart';
import '../providers/profile_provider.dart';
import '../services/database_service.dart';
import 'create_classroom_screen.dart';
import 'p2p_hub_screen.dart';
import 'student_dashboard_screen.dart';
import 'home_screen.dart';
import 'quiz_bank_screen.dart';
import 'teacher_dashboard_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<Classroom> _classrooms = [];
  Map<String, int> _postCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClassrooms();
  }

  Future<void> _loadClassrooms() async {
    final profile =
        Provider.of<ProfileProvider>(context, listen: false).profile;
    if (profile == null) return;

    List<Classroom> classrooms;
    if (profile.isTeacher) {
      classrooms = await _dbService.getClassroomsByTeacher(profile.deviceId);
    } else {
      classrooms = await _dbService.getJoinedClassrooms(profile.deviceId);
    }

    // Get post counts for each classroom
    final counts = <String, int>{};
    for (final c in classrooms) {
      counts[c.id] = await _dbService.getPostCount(c.id);
    }

    if (mounted) {
      setState(() {
        _classrooms = classrooms;
        _postCounts = counts;
        _isLoading = false;
      });
    }
  }

  void _openClassroom(Classroom classroom) {
    final profile =
        Provider.of<ProfileProvider>(context, listen: false).profile!;

    if (profile.isTeacher) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TeacherDashboardScreen(classroom: classroom),
        ),
      ).then((_) => _loadClassrooms()); // Refresh on return
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentDashboardScreen(classroom: classroom),
        ),
      ).then((_) => _loadClassrooms());
    }
  }

  void _logout() {
    final profileProvider =
        Provider.of<ProfileProvider>(context, listen: false);
    profileProvider.clearProfile();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context).profile;
    if (profile == null) return const SizedBox();

    return Scaffold(
      body: SafeArea(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header ───
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: profile.isTeacher
                              ? [
                                  const Color(0xFF6C63FF),
                                  const Color(0xFF9B93FF)
                                ]
                              : [
                                  const Color(0xFF00C9A7),
                                  const Color(0xFF00E4BF)
                                ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          profile.displayName[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hi, ${profile.displayName}!',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (profile.isTeacher
                                          ? const Color(0xFF6C63FF)
                                          : const Color(0xFF00C9A7))
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  profile.isTeacher ? 'Teacher' : 'Student',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: profile.isTeacher
                                        ? const Color(0xFF9B93FF)
                                        : const Color(0xFF00E4BF),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (profile.isTeacher)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                              const Color(0xFFFF8E53).withValues(alpha: 0.15),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFFF6B6B).withValues(alpha: 0.3),
                          ),
                        ),
                        child: IconButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const QuizBankScreen(),
                              ),
                            );
                          },
                          icon: const Icon(LucideIcons.fileQuestion,
                              color: Color(0xFFFF6B6B), size: 20),
                          tooltip: 'Quiz Bank',
                        ),
                      ),
                    const SizedBox(width: 4),
                     IconButton(
                      onPressed: _logout,
                      icon: const Icon(LucideIcons.logOut,
                          color: Colors.grey),
                      tooltip: 'Switch Account',
                    ),
                  ],
                ),
              ),

              // ─── Section Title ───
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  profile.isTeacher ? 'MY CLASSROOMS' : 'ENROLLED CLASSES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                ),
              ),

              // ─── Classroom List ───
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF6C63FF)))
                    : _classrooms.isEmpty
                        ? _buildEmptyState(profile.isTeacher)
                        : RefreshIndicator(
                            onRefresh: _loadClassrooms,
                            color: const Color(0xFF6C63FF),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 8),
                              itemCount: _classrooms.length,
                              itemBuilder: (context, index) {
                                return _buildClassroomCard(_classrooms[index])
                                    .animate()
                                    .fadeIn(delay: (index * 50).ms, duration: 400.ms)
                                    .slideX(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),

      // ─── FAB ───
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (profile.isTeacher) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CreateClassroomScreen()),
            );
          } else {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const P2PHubScreen()),
            );
          }
          _loadClassrooms(); // Refresh after returning
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: Icon(
          profile.isTeacher ? LucideIcons.plus : LucideIcons.radio,
        ),
        label: Text(
          profile.isTeacher ? 'Create Class' : 'Scan Nearby',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isTeacher) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(
              isTeacher ? LucideIcons.graduationCap : LucideIcons.search,
              size: 80,
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              isTeacher
                  ? 'No classrooms yet'
                  : 'No classes joined yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              isTeacher
                  ? 'Tap "Create Class" to get started'
                  : 'Tap "Scan Nearby" to find a classroom',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassroomCard(Classroom classroom) {
    final postCount = _postCounts[classroom.id] ?? 0;
    final profile =
        Provider.of<ProfileProvider>(context, listen: false).profile!;
    final isOwner = profile.isTeacher;

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openClassroom(classroom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                // Icon Container
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isOwner
                        ? colorScheme.primaryContainer
                        : colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isOwner ? LucideIcons.graduationCap : LucideIcons.bookOpen,
                    color: isOwner
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSecondaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        classroom.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                           Icon(
                            LucideIcons.fileText,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$postCount post${postCount == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(width: 12),
                          if (!isOwner) ...[
                             Icon(
                              LucideIcons.user,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                classroom.teacherName,
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
