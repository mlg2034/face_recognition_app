part of 'create_user_bloc.dart';

@immutable
sealed class CreateUserState {}

final class CreateUserInitial extends CreateUserState {}

final class CreateUserLoading extends CreateUserState {}

final class CreateUserError extends CreateUserState {
  final String error;

  CreateUserError({required this.error});
}

final class CreateUserSuccess extends CreateUserState {}
