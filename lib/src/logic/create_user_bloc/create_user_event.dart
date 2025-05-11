part of 'create_user_bloc.dart';

@immutable
sealed class CreateUserEvent {}

class CreateUser extends CreateUserEvent{
  final CreateUserDTO createUserDTO;
  CreateUser({
    required this.createUserDTO
});
}