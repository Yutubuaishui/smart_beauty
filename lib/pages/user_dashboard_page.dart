import 'package:flutter/material.dart';
import '../models/routine_reminder.dart';
import '../models/product.dart';
import '../widgets/routine_reminder_card.dart';
import '../widgets/product_card.dart';

class UserDashboardPage extends StatelessWidget {
  const UserDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Sample data - in production, this would come from a service/repository
    final upcomingReminders = [
      RoutineReminder(
        id: '1',
        title: 'Morning Skincare Routine',
        description: 'Cleanser, Toner, Moisturizer, and Sunscreen',
        scheduledTime: DateTime.now().add(const Duration(hours: 2)),
        routineType: 'morning',
      ),
      RoutineReminder(
        id: '2',
        title: 'Evening Skincare Routine',
        description: 'Double cleanse, Serum, Night cream',
        scheduledTime: DateTime.now().add(const Duration(hours: 10)),
        routineType: 'evening',
      ),
    ];

    final recommendedProducts = [
      Product(
        id: '1',
        name: 'Hydrating Face Serum',
        description: 'Deeply hydrating serum with hyaluronic acid',
        imageUrl: '',
        price: 29.99,
        rating: 4.5,
        category: 'Serum',
        brand: 'SmartBeauty',
      ),
      Product(
        id: '2',
        name: 'Vitamin C Brightening Cream',
        description: 'Brightens and evens skin tone',
        imageUrl: '',
        price: 34.99,
        rating: 4.8,
        category: 'Moisturizer',
        brand: 'SmartBeauty',
      ),
      Product(
        id: '3',
        name: 'Gentle Cleansing Foam',
        description: 'Removes impurities without stripping',
        imageUrl: '',
        price: 19.99,
        rating: 4.3,
        category: 'Cleanser',
        brand: 'SmartBeauty',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartBeauty AI'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // In production, refresh data here
          await Future.delayed(const Duration(seconds: 1));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Routine Reminders Section
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Routine Reminders',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Navigate to all reminders
                      },
                      child: const Text('View All'),
                    ),
                  ],
                ),
              ),
              if (upcomingReminders.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No upcoming reminders',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...upcomingReminders.map(
                  (reminder) => RoutineReminderCard(
                    reminder: reminder,
                    onComplete: () {
                      // Handle completion
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${reminder.title} marked as complete'),
                        ),
                      );
                    },
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // Recommended Products Section
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recommended Products',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Navigate to all products
                      },
                      child: const Text('View All'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 280,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: recommendedProducts.length,
                  itemBuilder: (context, index) {
                    return SizedBox(
                      width: 200,
                      child: ProductCard(
                        product: recommendedProducts[index],
                        onTap: () {
                          // Navigate to product details
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Viewing ${recommendedProducts[index].name}',
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
