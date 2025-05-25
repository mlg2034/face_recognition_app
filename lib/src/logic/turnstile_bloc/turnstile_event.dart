part of 'turnstile_bloc.dart';

@immutable
sealed class TurnstileEvent {}

class CallTurnstile extends TurnstileEvent{}

class ResetTurnstile extends TurnstileEvent{}