import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/classroom.dart';
import '../providers/profile_provider.dart';
import '../services/database_service.dart';
import 'create_classroom_screen.dart';
import 'p2p_hub_screen.dart';
import 'teacher_dashboard_screen.dart';
import 'student_dashboard_screen.dart';
import 'home_screen.dart';

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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0C29),
              Color(0xFF302B63),
              Color(0xFF24243E),
            ],
          ),
        ),
        child: SafeArea(
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
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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
                    IconButton(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded,
                          color: Colors.white54),
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
                    color: Colors.white.withValues(alpha: 0.4),
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
                                return _buildClassroomCard(
                                    _classrooms[index]);
                              },
                            ),
                          ),
              ),
            ],
          ),
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
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        icon: Icon(
          profile.isTeacher ? Icons.add_rounded : Icons.radar_rounded,
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
              isTeacher ? Icons.school_outlined : Icons.search_rounded,
              size: 80,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 24),
            Text(
              isTeacher
                  ? 'No classrooms yet'
                  : 'No classes joined yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isTeacher
                  ? 'Tap "Create Class" to get started'
                  : 'Tap "Scan Nearby" to find a classroom',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.3),
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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (isOwner
                        ? const Color(0xFF6C63FF)
                        : const Color(0xFF00C9A7))
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: (isOwner
                            ? const Color(0xFF6C63FF)
                            : const Color(0xFF00C9A7))
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isOwner
                        ? Icons.cast_for_education_rounded
                        : Icons.menu_book_rounded,
                    color: isOwner
                        ? const Color(0xFF6C63FF)
                        : const Color(0xFF00C9A7),
                    size: 26,
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$postCount post${postCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (!isOwner) ...[
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              classroom.teacherName,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white30,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
