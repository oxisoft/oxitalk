// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SyncState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SyncState()';
}


}

/// @nodoc
class $SyncStateCopyWith<$Res>  {
$SyncStateCopyWith(SyncState _, $Res Function(SyncState) __);
}


/// Adds pattern-matching-related methods to [SyncState].
extension SyncStatePatterns on SyncState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SyncState_Idle value)?  idle,TResult Function( SyncState_Running value)?  running,TResult Function( SyncState_Terminated value)?  terminated,TResult Function( SyncState_Error value)?  error,TResult Function( SyncState_Offline value)?  offline,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SyncState_Idle() when idle != null:
return idle(_that);case SyncState_Running() when running != null:
return running(_that);case SyncState_Terminated() when terminated != null:
return terminated(_that);case SyncState_Error() when error != null:
return error(_that);case SyncState_Offline() when offline != null:
return offline(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SyncState_Idle value)  idle,required TResult Function( SyncState_Running value)  running,required TResult Function( SyncState_Terminated value)  terminated,required TResult Function( SyncState_Error value)  error,required TResult Function( SyncState_Offline value)  offline,}){
final _that = this;
switch (_that) {
case SyncState_Idle():
return idle(_that);case SyncState_Running():
return running(_that);case SyncState_Terminated():
return terminated(_that);case SyncState_Error():
return error(_that);case SyncState_Offline():
return offline(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SyncState_Idle value)?  idle,TResult? Function( SyncState_Running value)?  running,TResult? Function( SyncState_Terminated value)?  terminated,TResult? Function( SyncState_Error value)?  error,TResult? Function( SyncState_Offline value)?  offline,}){
final _that = this;
switch (_that) {
case SyncState_Idle() when idle != null:
return idle(_that);case SyncState_Running() when running != null:
return running(_that);case SyncState_Terminated() when terminated != null:
return terminated(_that);case SyncState_Error() when error != null:
return error(_that);case SyncState_Offline() when offline != null:
return offline(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  running,TResult Function()?  terminated,TResult Function( CoreError error)?  error,TResult Function()?  offline,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SyncState_Idle() when idle != null:
return idle();case SyncState_Running() when running != null:
return running();case SyncState_Terminated() when terminated != null:
return terminated();case SyncState_Error() when error != null:
return error(_that.error);case SyncState_Offline() when offline != null:
return offline();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  running,required TResult Function()  terminated,required TResult Function( CoreError error)  error,required TResult Function()  offline,}) {final _that = this;
switch (_that) {
case SyncState_Idle():
return idle();case SyncState_Running():
return running();case SyncState_Terminated():
return terminated();case SyncState_Error():
return error(_that.error);case SyncState_Offline():
return offline();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  running,TResult? Function()?  terminated,TResult? Function( CoreError error)?  error,TResult? Function()?  offline,}) {final _that = this;
switch (_that) {
case SyncState_Idle() when idle != null:
return idle();case SyncState_Running() when running != null:
return running();case SyncState_Terminated() when terminated != null:
return terminated();case SyncState_Error() when error != null:
return error(_that.error);case SyncState_Offline() when offline != null:
return offline();case _:
  return null;

}
}

}

/// @nodoc


class SyncState_Idle extends SyncState {
  const SyncState_Idle(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncState_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SyncState.idle()';
}


}




/// @nodoc


class SyncState_Running extends SyncState {
  const SyncState_Running(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncState_Running);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SyncState.running()';
}


}




/// @nodoc


class SyncState_Terminated extends SyncState {
  const SyncState_Terminated(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncState_Terminated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SyncState.terminated()';
}


}




/// @nodoc


class SyncState_Error extends SyncState {
  const SyncState_Error({required this.error}): super._();
  

 final  CoreError error;

/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncState_ErrorCopyWith<SyncState_Error> get copyWith => _$SyncState_ErrorCopyWithImpl<SyncState_Error>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncState_Error&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'SyncState.error(error: $error)';
}


}

/// @nodoc
abstract mixin class $SyncState_ErrorCopyWith<$Res> implements $SyncStateCopyWith<$Res> {
  factory $SyncState_ErrorCopyWith(SyncState_Error value, $Res Function(SyncState_Error) _then) = _$SyncState_ErrorCopyWithImpl;
@useResult
$Res call({
 CoreError error
});


$CoreErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$SyncState_ErrorCopyWithImpl<$Res>
    implements $SyncState_ErrorCopyWith<$Res> {
  _$SyncState_ErrorCopyWithImpl(this._self, this._then);

  final SyncState_Error _self;
  final $Res Function(SyncState_Error) _then;

/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(SyncState_Error(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as CoreError,
  ));
}

/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CoreErrorCopyWith<$Res> get error {
  
  return $CoreErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class SyncState_Offline extends SyncState {
  const SyncState_Offline(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncState_Offline);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SyncState.offline()';
}


}




// dart format on
