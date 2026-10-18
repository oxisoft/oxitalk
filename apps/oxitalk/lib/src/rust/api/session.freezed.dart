// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionChange {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionChange);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SessionChange()';
}


}

/// @nodoc
class $SessionChangeCopyWith<$Res>  {
$SessionChangeCopyWith(SessionChange _, $Res Function(SessionChange) __);
}


/// Adds pattern-matching-related methods to [SessionChange].
extension SessionChangePatterns on SessionChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SessionChange_UnknownToken value)?  unknownToken,TResult Function( SessionChange_TokensRefreshed value)?  tokensRefreshed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SessionChange_UnknownToken() when unknownToken != null:
return unknownToken(_that);case SessionChange_TokensRefreshed() when tokensRefreshed != null:
return tokensRefreshed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SessionChange_UnknownToken value)  unknownToken,required TResult Function( SessionChange_TokensRefreshed value)  tokensRefreshed,}){
final _that = this;
switch (_that) {
case SessionChange_UnknownToken():
return unknownToken(_that);case SessionChange_TokensRefreshed():
return tokensRefreshed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SessionChange_UnknownToken value)?  unknownToken,TResult? Function( SessionChange_TokensRefreshed value)?  tokensRefreshed,}){
final _that = this;
switch (_that) {
case SessionChange_UnknownToken() when unknownToken != null:
return unknownToken(_that);case SessionChange_TokensRefreshed() when tokensRefreshed != null:
return tokensRefreshed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool softLogout)?  unknownToken,TResult Function()?  tokensRefreshed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SessionChange_UnknownToken() when unknownToken != null:
return unknownToken(_that.softLogout);case SessionChange_TokensRefreshed() when tokensRefreshed != null:
return tokensRefreshed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool softLogout)  unknownToken,required TResult Function()  tokensRefreshed,}) {final _that = this;
switch (_that) {
case SessionChange_UnknownToken():
return unknownToken(_that.softLogout);case SessionChange_TokensRefreshed():
return tokensRefreshed();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool softLogout)?  unknownToken,TResult? Function()?  tokensRefreshed,}) {final _that = this;
switch (_that) {
case SessionChange_UnknownToken() when unknownToken != null:
return unknownToken(_that.softLogout);case SessionChange_TokensRefreshed() when tokensRefreshed != null:
return tokensRefreshed();case _:
  return null;

}
}

}

/// @nodoc


class SessionChange_UnknownToken extends SessionChange {
  const SessionChange_UnknownToken({required this.softLogout}): super._();
  

 final  bool softLogout;

/// Create a copy of SessionChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionChange_UnknownTokenCopyWith<SessionChange_UnknownToken> get copyWith => _$SessionChange_UnknownTokenCopyWithImpl<SessionChange_UnknownToken>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionChange_UnknownToken&&(identical(other.softLogout, softLogout) || other.softLogout == softLogout));
}


@override
int get hashCode {
    return Object.hash(runtimeType,softLogout);
}

@override
String toString() {
    return 'SessionChange.unknownToken(softLogout: $softLogout)';
}


}

/// @nodoc
abstract mixin class $SessionChange_UnknownTokenCopyWith<$Res> implements $SessionChangeCopyWith<$Res> {
  factory $SessionChange_UnknownTokenCopyWith(SessionChange_UnknownToken value, $Res Function(SessionChange_UnknownToken) _then) = _$SessionChange_UnknownTokenCopyWithImpl;
@useResult
$Res call({
 bool softLogout
});




}
/// @nodoc
class _$SessionChange_UnknownTokenCopyWithImpl<$Res>
    implements $SessionChange_UnknownTokenCopyWith<$Res> {
  _$SessionChange_UnknownTokenCopyWithImpl(this._self, this._then);

  final SessionChange_UnknownToken _self;
  final $Res Function(SessionChange_UnknownToken) _then;

/// Create a copy of SessionChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? softLogout = null,}) {
  return _then(SessionChange_UnknownToken(
softLogout: null == softLogout ? _self.softLogout : softLogout // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class SessionChange_TokensRefreshed extends SessionChange {
  const SessionChange_TokensRefreshed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionChange_TokensRefreshed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SessionChange.tokensRefreshed()';
}


}




// dart format on
