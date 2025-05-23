part of 'turnstile_bloc.dart';

@immutable
sealed class TurnstileState {}

final class TurnstileInitial extends TurnstileState {}

final class TurnstileLoading extends TurnstileState{}

final class TurnstileError extends TurnstileState{
  final String error;
  TurnstileError(this.error);
}

final class TurnstileSuccess extends TurnstileState{}