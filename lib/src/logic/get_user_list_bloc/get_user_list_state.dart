part of 'get_user_list_bloc.dart';

@immutable
sealed class GetUserListState {}

final class GetUserListInitial extends GetUserListState {}

final class GetUserListLoading extends GetUserListState {}

final class GetUserListError extends GetUserListState {
  final String error;

  GetUserListError(this.error);
}

final class GetUserListSuccess extends GetUserListState {
  final List<UserModel> userList;

  GetUserListSuccess(this.userList);
}
