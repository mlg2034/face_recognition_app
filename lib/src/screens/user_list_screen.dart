import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_face_recognition/src/logic/get_user_list_bloc/get_user_list_bloc.dart';
import 'package:realtime_face_recognition/src/model/user_model.dart';

class UserListScreen extends StatelessWidget {
  const UserListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => GetUserListBloc()..add(GetUserList()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Распознанные пользователи'),
          backgroundColor: Colors.blue,
        ),
        body: BlocBuilder<GetUserListBloc, GetUserListState>(
          builder: (context, state) {
            if (state is GetUserListLoading) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            } else if (state is GetUserListSuccess) {
              return _buildUserList(state.userList);
            } else if (state is GetUserListError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 60, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Ошибка загрузки: ${state.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        context.read<GetUserListBloc>().add(GetUserList());
                      },
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              );
            }
            return const Center(
              child: Text('Нажмите кнопку для загрузки пользователей'),
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            context.read<GetUserListBloc>().add(GetUserList());
          },
          child: const Icon(Icons.refresh),
        ),
      ),
    );
  }

  Widget _buildUserList(List<UserModel> users) {
    if (users.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Пользователи не найдены',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Распознайте лицо, чтобы добавить пользователя',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final user = users[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue.shade100,
            child: const Icon(Icons.person, color: Colors.blue),
          ),
          title: Text(
            user.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            'ID: ${user.id}',
            style: const TextStyle(fontSize: 14),
          ),
          trailing: Text(
            'Время входа: ${_formatDateTime(user.entryTime)}',
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Не указано';
    return '${dateTime.day}.${dateTime.month}.${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }
} 