// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'verification.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VerificationFlowState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VerificationFlowState()';
}


}

/// @nodoc
class $VerificationFlowStateCopyWith<$Res>  {
$VerificationFlowStateCopyWith(VerificationFlowState _, $Res Function(VerificationFlowState) __);
}


/// Adds pattern-matching-related methods to [VerificationFlowState].
extension VerificationFlowStatePatterns on VerificationFlowState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( VerificationFlowState_Created value)?  created,TResult Function( VerificationFlowState_Requested value)?  requested,TResult Function( VerificationFlowState_Ready value)?  ready,TResult Function( VerificationFlowState_SasCreated value)?  sasCreated,TResult Function( VerificationFlowState_SasStarted value)?  sasStarted,TResult Function( VerificationFlowState_SasAccepted value)?  sasAccepted,TResult Function( VerificationFlowState_KeysExchanged value)?  keysExchanged,TResult Function( VerificationFlowState_Confirmed value)?  confirmed,TResult Function( VerificationFlowState_Done value)?  done,TResult Function( VerificationFlowState_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case VerificationFlowState_Created() when created != null:
return created(_that);case VerificationFlowState_Requested() when requested != null:
return requested(_that);case VerificationFlowState_Ready() when ready != null:
return ready(_that);case VerificationFlowState_SasCreated() when sasCreated != null:
return sasCreated(_that);case VerificationFlowState_SasStarted() when sasStarted != null:
return sasStarted(_that);case VerificationFlowState_SasAccepted() when sasAccepted != null:
return sasAccepted(_that);case VerificationFlowState_KeysExchanged() when keysExchanged != null:
return keysExchanged(_that);case VerificationFlowState_Confirmed() when confirmed != null:
return confirmed(_that);case VerificationFlowState_Done() when done != null:
return done(_that);case VerificationFlowState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( VerificationFlowState_Created value)  created,required TResult Function( VerificationFlowState_Requested value)  requested,required TResult Function( VerificationFlowState_Ready value)  ready,required TResult Function( VerificationFlowState_SasCreated value)  sasCreated,required TResult Function( VerificationFlowState_SasStarted value)  sasStarted,required TResult Function( VerificationFlowState_SasAccepted value)  sasAccepted,required TResult Function( VerificationFlowState_KeysExchanged value)  keysExchanged,required TResult Function( VerificationFlowState_Confirmed value)  confirmed,required TResult Function( VerificationFlowState_Done value)  done,required TResult Function( VerificationFlowState_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case VerificationFlowState_Created():
return created(_that);case VerificationFlowState_Requested():
return requested(_that);case VerificationFlowState_Ready():
return ready(_that);case VerificationFlowState_SasCreated():
return sasCreated(_that);case VerificationFlowState_SasStarted():
return sasStarted(_that);case VerificationFlowState_SasAccepted():
return sasAccepted(_that);case VerificationFlowState_KeysExchanged():
return keysExchanged(_that);case VerificationFlowState_Confirmed():
return confirmed(_that);case VerificationFlowState_Done():
return done(_that);case VerificationFlowState_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( VerificationFlowState_Created value)?  created,TResult? Function( VerificationFlowState_Requested value)?  requested,TResult? Function( VerificationFlowState_Ready value)?  ready,TResult? Function( VerificationFlowState_SasCreated value)?  sasCreated,TResult? Function( VerificationFlowState_SasStarted value)?  sasStarted,TResult? Function( VerificationFlowState_SasAccepted value)?  sasAccepted,TResult? Function( VerificationFlowState_KeysExchanged value)?  keysExchanged,TResult? Function( VerificationFlowState_Confirmed value)?  confirmed,TResult? Function( VerificationFlowState_Done value)?  done,TResult? Function( VerificationFlowState_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case VerificationFlowState_Created() when created != null:
return created(_that);case VerificationFlowState_Requested() when requested != null:
return requested(_that);case VerificationFlowState_Ready() when ready != null:
return ready(_that);case VerificationFlowState_SasCreated() when sasCreated != null:
return sasCreated(_that);case VerificationFlowState_SasStarted() when sasStarted != null:
return sasStarted(_that);case VerificationFlowState_SasAccepted() when sasAccepted != null:
return sasAccepted(_that);case VerificationFlowState_KeysExchanged() when keysExchanged != null:
return keysExchanged(_that);case VerificationFlowState_Confirmed() when confirmed != null:
return confirmed(_that);case VerificationFlowState_Done() when done != null:
return done(_that);case VerificationFlowState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  created,TResult Function()?  requested,TResult Function()?  ready,TResult Function()?  sasCreated,TResult Function()?  sasStarted,TResult Function()?  sasAccepted,TResult Function( List<VerificationEmoji>? emojis,  Uint16List decimals)?  keysExchanged,TResult Function()?  confirmed,TResult Function()?  done,TResult Function( String reason,  bool byUs)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case VerificationFlowState_Created() when created != null:
return created();case VerificationFlowState_Requested() when requested != null:
return requested();case VerificationFlowState_Ready() when ready != null:
return ready();case VerificationFlowState_SasCreated() when sasCreated != null:
return sasCreated();case VerificationFlowState_SasStarted() when sasStarted != null:
return sasStarted();case VerificationFlowState_SasAccepted() when sasAccepted != null:
return sasAccepted();case VerificationFlowState_KeysExchanged() when keysExchanged != null:
return keysExchanged(_that.emojis,_that.decimals);case VerificationFlowState_Confirmed() when confirmed != null:
return confirmed();case VerificationFlowState_Done() when done != null:
return done();case VerificationFlowState_Cancelled() when cancelled != null:
return cancelled(_that.reason,_that.byUs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  created,required TResult Function()  requested,required TResult Function()  ready,required TResult Function()  sasCreated,required TResult Function()  sasStarted,required TResult Function()  sasAccepted,required TResult Function( List<VerificationEmoji>? emojis,  Uint16List decimals)  keysExchanged,required TResult Function()  confirmed,required TResult Function()  done,required TResult Function( String reason,  bool byUs)  cancelled,}) {final _that = this;
switch (_that) {
case VerificationFlowState_Created():
return created();case VerificationFlowState_Requested():
return requested();case VerificationFlowState_Ready():
return ready();case VerificationFlowState_SasCreated():
return sasCreated();case VerificationFlowState_SasStarted():
return sasStarted();case VerificationFlowState_SasAccepted():
return sasAccepted();case VerificationFlowState_KeysExchanged():
return keysExchanged(_that.emojis,_that.decimals);case VerificationFlowState_Confirmed():
return confirmed();case VerificationFlowState_Done():
return done();case VerificationFlowState_Cancelled():
return cancelled(_that.reason,_that.byUs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  created,TResult? Function()?  requested,TResult? Function()?  ready,TResult? Function()?  sasCreated,TResult? Function()?  sasStarted,TResult? Function()?  sasAccepted,TResult? Function( List<VerificationEmoji>? emojis,  Uint16List decimals)?  keysExchanged,TResult? Function()?  confirmed,TResult? Function()?  done,TResult? Function( String reason,  bool byUs)?  cancelled,}) {final _that = this;
switch (_that) {
case VerificationFlowState_Created() when created != null:
return created();case VerificationFlowState_Requested() when requested != null:
return requested();case VerificationFlowState_Ready() when ready != null:
return ready();case VerificationFlowState_SasCreated() when sasCreated != null:
return sasCreated();case VerificationFlowState_SasStarted() when sasStarted != null:
return sasStarted();case VerificationFlowState_SasAccepted() when sasAccepted != null:
return sasAccepted();case VerificationFlowState_KeysExchanged() when keysExchanged != null:
return keysExchanged(_that.emojis,_that.decimals);case VerificationFlowState_Confirmed() when confirmed != null:
return confirmed();case VerificationFlowState_Done() when done != null:
return done();case VerificationFlowState_Cancelled() when cancelled != null:
return cancelled(_that.reason,_that.byUs);case _:
  return null;

}
}

}

/// @nodoc


class VerificationFlowState_Created extends VerificationFlowState {
  const VerificationFlowState_Created(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_Created);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VerificationFlowState.created()';
}


}




/// @nodoc


class VerificationFlowState_Requested extends VerificationFlowState {
  const VerificationFlowState_Requested(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_Requested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VerificationFlowState.requested()';
}


}




/// @nodoc


class VerificationFlowState_Ready extends VerificationFlowState {
  const VerificationFlowState_Ready(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_Ready);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VerificationFlowState.ready()';
}


}




/// @nodoc


class VerificationFlowState_SasCreated extends VerificationFlowState {
  const VerificationFlowState_SasCreated(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_SasCreated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VerificationFlowState.sasCreated()';
}


}




/// @nodoc


class VerificationFlowState_SasStarted extends VerificationFlowState {
  const VerificationFlowState_SasStarted(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_SasStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VerificationFlowState.sasStarted()';
}


}




/// @nodoc


class VerificationFlowState_SasAccepted extends VerificationFlowState {
  const VerificationFlowState_SasAccepted(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_SasAccepted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VerificationFlowState.sasAccepted()';
}


}




/// @nodoc


class VerificationFlowState_KeysExchanged extends VerificationFlowState {
  const VerificationFlowState_KeysExchanged({ List<VerificationEmoji>? emojis, required this.decimals}): _emojis = emojis,super._();
  

 final  List<VerificationEmoji>? _emojis;
 List<VerificationEmoji>? get emojis {
  final value = _emojis;
  if (value == null) return null;
  if (_emojis is EqualUnmodifiableListView) return _emojis;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  Uint16List decimals;

/// Create a copy of VerificationFlowState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VerificationFlowState_KeysExchangedCopyWith<VerificationFlowState_KeysExchanged> get copyWith => _$VerificationFlowState_KeysExchangedCopyWithImpl<VerificationFlowState_KeysExchanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_KeysExchanged&&const DeepCollectionEquality().equals(other.emojis, _emojis)&&const DeepCollectionEquality().equals(other.decimals, decimals));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_emojis),const DeepCollectionEquality().hash(decimals));
}

@override
String toString() {
    return 'VerificationFlowState.keysExchanged(emojis: $emojis, decimals: $decimals)';
}


}

/// @nodoc
abstract mixin class $VerificationFlowState_KeysExchangedCopyWith<$Res> implements $VerificationFlowStateCopyWith<$Res> {
  factory $VerificationFlowState_KeysExchangedCopyWith(VerificationFlowState_KeysExchanged value, $Res Function(VerificationFlowState_KeysExchanged) _then) = _$VerificationFlowState_KeysExchangedCopyWithImpl;
@useResult
$Res call({
 List<VerificationEmoji>? emojis, Uint16List decimals
});




}
/// @nodoc
class _$VerificationFlowState_KeysExchangedCopyWithImpl<$Res>
    implements $VerificationFlowState_KeysExchangedCopyWith<$Res> {
  _$VerificationFlowState_KeysExchangedCopyWithImpl(this._self, this._then);

  final VerificationFlowState_KeysExchanged _self;
  final $Res Function(VerificationFlowState_KeysExchanged) _then;

/// Create a copy of VerificationFlowState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? emojis = freezed,Object? decimals = null,}) {
  return _then(VerificationFlowState_KeysExchanged(
emojis: freezed == emojis ? _self._emojis : emojis // ignore: cast_nullable_to_non_nullable
as List<VerificationEmoji>?,decimals: null == decimals ? _self.decimals : decimals // ignore: cast_nullable_to_non_nullable
as Uint16List,
  ));
}


}

/// @nodoc


class VerificationFlowState_Confirmed extends VerificationFlowState {
  const VerificationFlowState_Confirmed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_Confirmed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VerificationFlowState.confirmed()';
}


}




/// @nodoc


class VerificationFlowState_Done extends VerificationFlowState {
  const VerificationFlowState_Done(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_Done);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VerificationFlowState.done()';
}


}




/// @nodoc


class VerificationFlowState_Cancelled extends VerificationFlowState {
  const VerificationFlowState_Cancelled({required this.reason, required this.byUs}): super._();
  

 final  String reason;
 final  bool byUs;

/// Create a copy of VerificationFlowState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VerificationFlowState_CancelledCopyWith<VerificationFlowState_Cancelled> get copyWith => _$VerificationFlowState_CancelledCopyWithImpl<VerificationFlowState_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerificationFlowState_Cancelled&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.byUs, byUs) || other.byUs == byUs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason,byUs);
}

@override
String toString() {
    return 'VerificationFlowState.cancelled(reason: $reason, byUs: $byUs)';
}


}

/// @nodoc
abstract mixin class $VerificationFlowState_CancelledCopyWith<$Res> implements $VerificationFlowStateCopyWith<$Res> {
  factory $VerificationFlowState_CancelledCopyWith(VerificationFlowState_Cancelled value, $Res Function(VerificationFlowState_Cancelled) _then) = _$VerificationFlowState_CancelledCopyWithImpl;
@useResult
$Res call({
 String reason, bool byUs
});




}
/// @nodoc
class _$VerificationFlowState_CancelledCopyWithImpl<$Res>
    implements $VerificationFlowState_CancelledCopyWith<$Res> {
  _$VerificationFlowState_CancelledCopyWithImpl(this._self, this._then);

  final VerificationFlowState_Cancelled _self;
  final $Res Function(VerificationFlowState_Cancelled) _then;

/// Create a copy of VerificationFlowState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,Object? byUs = null,}) {
  return _then(VerificationFlowState_Cancelled(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,byUs: null == byUs ? _self.byUs : byUs // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
