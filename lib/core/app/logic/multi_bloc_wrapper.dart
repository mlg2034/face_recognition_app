import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_face_recognition/src/logic/create_user_bloc/create_user_bloc.dart';
import 'package:realtime_face_recognition/src/logic/get_user_list_bloc/get_user_list_bloc.dart';

class MultiBlocWrapper extends StatelessWidget {
  final Widget child;

  const MultiBlocWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => CreateUserBloc()),
        BlocProvider(create: (context) => GetUserListBloc()),
      ],
      child: Builder(builder: (context) {
        return child;
      }),
    );
  }
}
