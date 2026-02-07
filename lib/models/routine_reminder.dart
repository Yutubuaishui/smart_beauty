class RoutineReminder {
  final String id;
  final String title;
  final String description;
  final DateTime scheduledTime;
  final bool isCompleted;
  final String routineType; // e.g., 'morning', 'evening', 'weekly'

  RoutineReminder({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledTime,
    this.isCompleted = false,
    required this.routineType,
  });
}
