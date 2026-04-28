import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../services/service_provider.dart';

class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({super.key});

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ServiceProvider.of(context).assignmentService.fetchAssignments();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assignmentService = ServiceProvider.of(context).assignmentService;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => assignmentService.fetchAssignments(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: assignmentService,
        builder: (context, _) {
          if (assignmentService.loading && assignmentService.assignments.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (assignmentService.assignments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No upcoming assignments',
                    style: theme.textTheme.titleMedium,
                  ),
                  if (assignmentService.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      assignmentService.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ]
                ],
              ),
            );
          }

          final assignments = assignmentService.assignments.toList()
            ..sort((a, b) => a.due.compareTo(b.due));

          return RefreshIndicator(
            onRefresh: () => assignmentService.fetchAssignments(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: assignments.length + (assignmentService.error != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0 && assignmentService.error != null) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Error syncing: ${assignmentService.error}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  );
                }

                final itemIndex = assignmentService.error != null ? index - 1 : index;
                final assignment = assignments[itemIndex];
                return _AssignmentCard(assignment: assignment);
              },
            ),
          );
        },
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final Assignment assignment;

  const _AssignmentCard({required this.assignment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isPast = assignment.due.isBefore(now);
    
    // Formatting the date nicely
    final DateFormat formatter = DateFormat('MM/dd HH:mm');
    final dueString = formatter.format(assignment.due);

    Color getStatusColor() {
      if (assignment.submitted) return Colors.green;
      if (isPast) return Colors.red;
      final hoursLeft = assignment.due.difference(now).inHours;
      if (hoursLeft < 24) return Colors.orange;
      return theme.colorScheme.primary;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: assignment.url != null ? () {} : null, // Future: open URL
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      assignment.platform.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (assignment.status != null)
                    Text(
                      assignment.status!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: getStatusColor(),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                assignment.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                assignment.course,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: isPast && !assignment.submitted 
                        ? Colors.red 
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Due: $dueString',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isPast && !assignment.submitted 
                          ? Colors.red 
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isPast && !assignment.submitted 
                          ? FontWeight.bold 
                          : FontWeight.normal,
                    ),
                  ),
                  const Spacer(),
                  if (assignment.submitted)
                    Row(
                      children: [
                        const Icon(Icons.check_circle, size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          'Submitted',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
