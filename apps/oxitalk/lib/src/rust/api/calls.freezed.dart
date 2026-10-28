// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'calls.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$IncomingCallUpdate {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IncomingCallUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'IncomingCallUpdate()';
}


}

/// @nodoc
class $IncomingCallUpdateCopyWith<$Res>  {
$IncomingCallUpdateCopyWith(IncomingCallUpdate _, $Res Function(IncomingCallUpdate) __);
}


/// Adds pattern-matching-related methods to [IncomingCallUpdate].
extension IncomingCallUpdatePatterns on IncomingCallUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IncomingCallUpdate_Ringing value)?  ringing,TResult Function( IncomingCallUpdate_Ended value)?  ended,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IncomingCallUpdate_Ringing() when ringing != null:
return ringing(_that);case IncomingCallUpdate_Ended() when ended != null:
return ended(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IncomingCallUpdate_Ringing value)  ringing,required TResult Function( IncomingCallUpdate_Ended value)  ended,}){
final _that = this;
switch (_that) {
case IncomingCallUpdate_Ringing():
return ringing(_that);case IncomingCallUpdate_Ended():
return ended(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IncomingCallUpdate_Ringing value)?  ringing,TResult? Function( IncomingCallUpdate_Ended value)?  ended,}){
final _that = this;
switch (_that) {
case IncomingCallUpdate_Ringing() when ringing != null:
return ringing(_that);case IncomingCallUpdate_Ended() when ended != null:
return ended(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( IncomingCall call)?  ringing,TResult Function( String roomId,  String notificationEventId,  IncomingCallEnd reason)?  ended,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IncomingCallUpdate_Ringing() when ringing != null:
return ringing(_that.call);case IncomingCallUpdate_Ended() when ended != null:
return ended(_that.roomId,_that.notificationEventId,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( IncomingCall call)  ringing,required TResult Function( String roomId,  String notificationEventId,  IncomingCallEnd reason)  ended,}) {final _that = this;
switch (_that) {
case IncomingCallUpdate_Ringing():
return ringing(_that.call);case IncomingCallUpdate_Ended():
return ended(_that.roomId,_that.notificationEventId,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( IncomingCall call)?  ringing,TResult? Function( String roomId,  String notificationEventId,  IncomingCallEnd reason)?  ended,}) {final _that = this;
switch (_that) {
case IncomingCallUpdate_Ringing() when ringing != null:
return ringing(_that.call);case IncomingCallUpdate_Ended() when ended != null:
return ended(_that.roomId,_that.notificationEventId,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class IncomingCallUpdate_Ringing extends IncomingCallUpdate {
  const IncomingCallUpdate_Ringing({required this.call}): super._();
  

 final  IncomingCall call;

/// Create a copy of IncomingCallUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IncomingCallUpdate_RingingCopyWith<IncomingCallUpdate_Ringing> get copyWith => _$IncomingCallUpdate_RingingCopyWithImpl<IncomingCallUpdate_Ringing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IncomingCallUpdate_Ringing&&(identical(other.call, call) || other.call == call));
}


@override
int get hashCode {
    return Object.hash(runtimeType,call);
}

@override
String toString() {
    return 'IncomingCallUpdate.ringing(call: $call)';
}


}

/// @nodoc
abstract mixin class $IncomingCallUpdate_RingingCopyWith<$Res> implements $IncomingCallUpdateCopyWith<$Res> {
  factory $IncomingCallUpdate_RingingCopyWith(IncomingCallUpdate_Ringing value, $Res Function(IncomingCallUpdate_Ringing) _then) = _$IncomingCallUpdate_RingingCopyWithImpl;
@useResult
$Res call({
 IncomingCall call
});




}
/// @nodoc
class _$IncomingCallUpdate_RingingCopyWithImpl<$Res>
    implements $IncomingCallUpdate_RingingCopyWith<$Res> {
  _$IncomingCallUpdate_RingingCopyWithImpl(this._self, this._then);

  final IncomingCallUpdate_Ringing _self;
  final $Res Function(IncomingCallUpdate_Ringing) _then;

/// Create a copy of IncomingCallUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? call = null,}) {
  return _then(IncomingCallUpdate_Ringing(
call: null == call ? _self.call : call // ignore: cast_nullable_to_non_nullable
as IncomingCall,
  ));
}


}

/// @nodoc


class IncomingCallUpdate_Ended extends IncomingCallUpdate {
  const IncomingCallUpdate_Ended({required this.roomId, required this.notificationEventId, required this.reason}): super._();
  

 final  String roomId;
 final  String notificationEventId;
 final  IncomingCallEnd reason;

/// Create a copy of IncomingCallUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IncomingCallUpdate_EndedCopyWith<IncomingCallUpdate_Ended> get copyWith => _$IncomingCallUpdate_EndedCopyWithImpl<IncomingCallUpdate_Ended>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IncomingCallUpdate_Ended&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.notificationEventId, notificationEventId) || other.notificationEventId == notificationEventId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,roomId,notificationEventId,reason);
}

@override
String toString() {
    return 'IncomingCallUpdate.ended(roomId: $roomId, notificationEventId: $notificationEventId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $IncomingCallUpdate_EndedCopyWith<$Res> implements $IncomingCallUpdateCopyWith<$Res> {
  factory $IncomingCallUpdate_EndedCopyWith(IncomingCallUpdate_Ended value, $Res Function(IncomingCallUpdate_Ended) _then) = _$IncomingCallUpdate_EndedCopyWithImpl;
@useResult
$Res call({
 String roomId, String notificationEventId, IncomingCallEnd reason
});




}
/// @nodoc
class _$IncomingCallUpdate_EndedCopyWithImpl<$Res>
    implements $IncomingCallUpdate_EndedCopyWith<$Res> {
  _$IncomingCallUpdate_EndedCopyWithImpl(this._self, this._then);

  final IncomingCallUpdate_Ended _self;
  final $Res Function(IncomingCallUpdate_Ended) _then;

/// Create a copy of IncomingCallUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? notificationEventId = null,Object? reason = null,}) {
  return _then(IncomingCallUpdate_Ended(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,notificationEventId: null == notificationEventId ? _self.notificationEventId : notificationEventId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as IncomingCallEnd,
  ));
}


}

// dart format on
