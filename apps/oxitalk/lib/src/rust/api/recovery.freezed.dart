// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recovery.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RecoveryProgress {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryProgress);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RecoveryProgress()';
}


}

/// @nodoc
class $RecoveryProgressCopyWith<$Res>  {
$RecoveryProgressCopyWith(RecoveryProgress _, $Res Function(RecoveryProgress) __);
}


/// Adds pattern-matching-related methods to [RecoveryProgress].
extension RecoveryProgressPatterns on RecoveryProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RecoveryProgress_Starting value)?  starting,TResult Function( RecoveryProgress_CreatingBackup value)?  creatingBackup,TResult Function( RecoveryProgress_CreatingRecoveryKey value)?  creatingRecoveryKey,TResult Function( RecoveryProgress_BackingUp value)?  backingUp,TResult Function( RecoveryProgress_BackupFailed value)?  backupFailed,TResult Function( RecoveryProgress_Done value)?  done,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RecoveryProgress_Starting() when starting != null:
return starting(_that);case RecoveryProgress_CreatingBackup() when creatingBackup != null:
return creatingBackup(_that);case RecoveryProgress_CreatingRecoveryKey() when creatingRecoveryKey != null:
return creatingRecoveryKey(_that);case RecoveryProgress_BackingUp() when backingUp != null:
return backingUp(_that);case RecoveryProgress_BackupFailed() when backupFailed != null:
return backupFailed(_that);case RecoveryProgress_Done() when done != null:
return done(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RecoveryProgress_Starting value)  starting,required TResult Function( RecoveryProgress_CreatingBackup value)  creatingBackup,required TResult Function( RecoveryProgress_CreatingRecoveryKey value)  creatingRecoveryKey,required TResult Function( RecoveryProgress_BackingUp value)  backingUp,required TResult Function( RecoveryProgress_BackupFailed value)  backupFailed,required TResult Function( RecoveryProgress_Done value)  done,}){
final _that = this;
switch (_that) {
case RecoveryProgress_Starting():
return starting(_that);case RecoveryProgress_CreatingBackup():
return creatingBackup(_that);case RecoveryProgress_CreatingRecoveryKey():
return creatingRecoveryKey(_that);case RecoveryProgress_BackingUp():
return backingUp(_that);case RecoveryProgress_BackupFailed():
return backupFailed(_that);case RecoveryProgress_Done():
return done(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RecoveryProgress_Starting value)?  starting,TResult? Function( RecoveryProgress_CreatingBackup value)?  creatingBackup,TResult? Function( RecoveryProgress_CreatingRecoveryKey value)?  creatingRecoveryKey,TResult? Function( RecoveryProgress_BackingUp value)?  backingUp,TResult? Function( RecoveryProgress_BackupFailed value)?  backupFailed,TResult? Function( RecoveryProgress_Done value)?  done,}){
final _that = this;
switch (_that) {
case RecoveryProgress_Starting() when starting != null:
return starting(_that);case RecoveryProgress_CreatingBackup() when creatingBackup != null:
return creatingBackup(_that);case RecoveryProgress_CreatingRecoveryKey() when creatingRecoveryKey != null:
return creatingRecoveryKey(_that);case RecoveryProgress_BackingUp() when backingUp != null:
return backingUp(_that);case RecoveryProgress_BackupFailed() when backupFailed != null:
return backupFailed(_that);case RecoveryProgress_Done() when done != null:
return done(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  starting,TResult Function()?  creatingBackup,TResult Function()?  creatingRecoveryKey,TResult Function( int backedUp,  int total)?  backingUp,TResult Function()?  backupFailed,TResult Function()?  done,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RecoveryProgress_Starting() when starting != null:
return starting();case RecoveryProgress_CreatingBackup() when creatingBackup != null:
return creatingBackup();case RecoveryProgress_CreatingRecoveryKey() when creatingRecoveryKey != null:
return creatingRecoveryKey();case RecoveryProgress_BackingUp() when backingUp != null:
return backingUp(_that.backedUp,_that.total);case RecoveryProgress_BackupFailed() when backupFailed != null:
return backupFailed();case RecoveryProgress_Done() when done != null:
return done();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  starting,required TResult Function()  creatingBackup,required TResult Function()  creatingRecoveryKey,required TResult Function( int backedUp,  int total)  backingUp,required TResult Function()  backupFailed,required TResult Function()  done,}) {final _that = this;
switch (_that) {
case RecoveryProgress_Starting():
return starting();case RecoveryProgress_CreatingBackup():
return creatingBackup();case RecoveryProgress_CreatingRecoveryKey():
return creatingRecoveryKey();case RecoveryProgress_BackingUp():
return backingUp(_that.backedUp,_that.total);case RecoveryProgress_BackupFailed():
return backupFailed();case RecoveryProgress_Done():
return done();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  starting,TResult? Function()?  creatingBackup,TResult? Function()?  creatingRecoveryKey,TResult? Function( int backedUp,  int total)?  backingUp,TResult? Function()?  backupFailed,TResult? Function()?  done,}) {final _that = this;
switch (_that) {
case RecoveryProgress_Starting() when starting != null:
return starting();case RecoveryProgress_CreatingBackup() when creatingBackup != null:
return creatingBackup();case RecoveryProgress_CreatingRecoveryKey() when creatingRecoveryKey != null:
return creatingRecoveryKey();case RecoveryProgress_BackingUp() when backingUp != null:
return backingUp(_that.backedUp,_that.total);case RecoveryProgress_BackupFailed() when backupFailed != null:
return backupFailed();case RecoveryProgress_Done() when done != null:
return done();case _:
  return null;

}
}

}

/// @nodoc


class RecoveryProgress_Starting extends RecoveryProgress {
  const RecoveryProgress_Starting(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryProgress_Starting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RecoveryProgress.starting()';
}


}




/// @nodoc


class RecoveryProgress_CreatingBackup extends RecoveryProgress {
  const RecoveryProgress_CreatingBackup(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryProgress_CreatingBackup);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RecoveryProgress.creatingBackup()';
}


}




/// @nodoc


class RecoveryProgress_CreatingRecoveryKey extends RecoveryProgress {
  const RecoveryProgress_CreatingRecoveryKey(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryProgress_CreatingRecoveryKey);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RecoveryProgress.creatingRecoveryKey()';
}


}




/// @nodoc


class RecoveryProgress_BackingUp extends RecoveryProgress {
  const RecoveryProgress_BackingUp({required this.backedUp, required this.total}): super._();
  

 final  int backedUp;
 final  int total;

/// Create a copy of RecoveryProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryProgress_BackingUpCopyWith<RecoveryProgress_BackingUp> get copyWith => _$RecoveryProgress_BackingUpCopyWithImpl<RecoveryProgress_BackingUp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryProgress_BackingUp&&(identical(other.backedUp, backedUp) || other.backedUp == backedUp)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,backedUp,total);
}

@override
String toString() {
    return 'RecoveryProgress.backingUp(backedUp: $backedUp, total: $total)';
}


}

/// @nodoc
abstract mixin class $RecoveryProgress_BackingUpCopyWith<$Res> implements $RecoveryProgressCopyWith<$Res> {
  factory $RecoveryProgress_BackingUpCopyWith(RecoveryProgress_BackingUp value, $Res Function(RecoveryProgress_BackingUp) _then) = _$RecoveryProgress_BackingUpCopyWithImpl;
@useResult
$Res call({
 int backedUp, int total
});




}
/// @nodoc
class _$RecoveryProgress_BackingUpCopyWithImpl<$Res>
    implements $RecoveryProgress_BackingUpCopyWith<$Res> {
  _$RecoveryProgress_BackingUpCopyWithImpl(this._self, this._then);

  final RecoveryProgress_BackingUp _self;
  final $Res Function(RecoveryProgress_BackingUp) _then;

/// Create a copy of RecoveryProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? backedUp = null,Object? total = null,}) {
  return _then(RecoveryProgress_BackingUp(
backedUp: null == backedUp ? _self.backedUp : backedUp // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RecoveryProgress_BackupFailed extends RecoveryProgress {
  const RecoveryProgress_BackupFailed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryProgress_BackupFailed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RecoveryProgress.backupFailed()';
}


}




/// @nodoc


class RecoveryProgress_Done extends RecoveryProgress {
  const RecoveryProgress_Done(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryProgress_Done);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RecoveryProgress.done()';
}


}




// dart format on
