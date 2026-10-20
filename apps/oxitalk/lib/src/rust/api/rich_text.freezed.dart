// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'rich_text.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BlockKind {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockKind);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BlockKind()';
}


}

/// @nodoc
class $BlockKindCopyWith<$Res>  {
$BlockKindCopyWith(BlockKind _, $Res Function(BlockKind) __);
}


/// Adds pattern-matching-related methods to [BlockKind].
extension BlockKindPatterns on BlockKind {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BlockKind_Paragraph value)?  paragraph,TResult Function( BlockKind_Heading value)?  heading,TResult Function( BlockKind_ListItem value)?  listItem,TResult Function( BlockKind_Code value)?  code,TResult Function( BlockKind_Rule value)?  rule,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BlockKind_Paragraph() when paragraph != null:
return paragraph(_that);case BlockKind_Heading() when heading != null:
return heading(_that);case BlockKind_ListItem() when listItem != null:
return listItem(_that);case BlockKind_Code() when code != null:
return code(_that);case BlockKind_Rule() when rule != null:
return rule(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BlockKind_Paragraph value)  paragraph,required TResult Function( BlockKind_Heading value)  heading,required TResult Function( BlockKind_ListItem value)  listItem,required TResult Function( BlockKind_Code value)  code,required TResult Function( BlockKind_Rule value)  rule,}){
final _that = this;
switch (_that) {
case BlockKind_Paragraph():
return paragraph(_that);case BlockKind_Heading():
return heading(_that);case BlockKind_ListItem():
return listItem(_that);case BlockKind_Code():
return code(_that);case BlockKind_Rule():
return rule(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BlockKind_Paragraph value)?  paragraph,TResult? Function( BlockKind_Heading value)?  heading,TResult? Function( BlockKind_ListItem value)?  listItem,TResult? Function( BlockKind_Code value)?  code,TResult? Function( BlockKind_Rule value)?  rule,}){
final _that = this;
switch (_that) {
case BlockKind_Paragraph() when paragraph != null:
return paragraph(_that);case BlockKind_Heading() when heading != null:
return heading(_that);case BlockKind_ListItem() when listItem != null:
return listItem(_that);case BlockKind_Code() when code != null:
return code(_that);case BlockKind_Rule() when rule != null:
return rule(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  paragraph,TResult Function( int level)?  heading,TResult Function( int? number,  int depth)?  listItem,TResult Function( String? language)?  code,TResult Function()?  rule,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BlockKind_Paragraph() when paragraph != null:
return paragraph();case BlockKind_Heading() when heading != null:
return heading(_that.level);case BlockKind_ListItem() when listItem != null:
return listItem(_that.number,_that.depth);case BlockKind_Code() when code != null:
return code(_that.language);case BlockKind_Rule() when rule != null:
return rule();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  paragraph,required TResult Function( int level)  heading,required TResult Function( int? number,  int depth)  listItem,required TResult Function( String? language)  code,required TResult Function()  rule,}) {final _that = this;
switch (_that) {
case BlockKind_Paragraph():
return paragraph();case BlockKind_Heading():
return heading(_that.level);case BlockKind_ListItem():
return listItem(_that.number,_that.depth);case BlockKind_Code():
return code(_that.language);case BlockKind_Rule():
return rule();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  paragraph,TResult? Function( int level)?  heading,TResult? Function( int? number,  int depth)?  listItem,TResult? Function( String? language)?  code,TResult? Function()?  rule,}) {final _that = this;
switch (_that) {
case BlockKind_Paragraph() when paragraph != null:
return paragraph();case BlockKind_Heading() when heading != null:
return heading(_that.level);case BlockKind_ListItem() when listItem != null:
return listItem(_that.number,_that.depth);case BlockKind_Code() when code != null:
return code(_that.language);case BlockKind_Rule() when rule != null:
return rule();case _:
  return null;

}
}

}

/// @nodoc


class BlockKind_Paragraph extends BlockKind {
  const BlockKind_Paragraph(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockKind_Paragraph);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BlockKind.paragraph()';
}


}




/// @nodoc


class BlockKind_Heading extends BlockKind {
  const BlockKind_Heading({required this.level}): super._();
  

 final  int level;

/// Create a copy of BlockKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockKind_HeadingCopyWith<BlockKind_Heading> get copyWith => _$BlockKind_HeadingCopyWithImpl<BlockKind_Heading>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockKind_Heading&&(identical(other.level, level) || other.level == level));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level);
}

@override
String toString() {
    return 'BlockKind.heading(level: $level)';
}


}

/// @nodoc
abstract mixin class $BlockKind_HeadingCopyWith<$Res> implements $BlockKindCopyWith<$Res> {
  factory $BlockKind_HeadingCopyWith(BlockKind_Heading value, $Res Function(BlockKind_Heading) _then) = _$BlockKind_HeadingCopyWithImpl;
@useResult
$Res call({
 int level
});




}
/// @nodoc
class _$BlockKind_HeadingCopyWithImpl<$Res>
    implements $BlockKind_HeadingCopyWith<$Res> {
  _$BlockKind_HeadingCopyWithImpl(this._self, this._then);

  final BlockKind_Heading _self;
  final $Res Function(BlockKind_Heading) _then;

/// Create a copy of BlockKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? level = null,}) {
  return _then(BlockKind_Heading(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BlockKind_ListItem extends BlockKind {
  const BlockKind_ListItem({this.number, required this.depth}): super._();
  

 final  int? number;
 final  int depth;

/// Create a copy of BlockKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockKind_ListItemCopyWith<BlockKind_ListItem> get copyWith => _$BlockKind_ListItemCopyWithImpl<BlockKind_ListItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockKind_ListItem&&(identical(other.number, number) || other.number == number)&&(identical(other.depth, depth) || other.depth == depth));
}


@override
int get hashCode {
    return Object.hash(runtimeType,number,depth);
}

@override
String toString() {
    return 'BlockKind.listItem(number: $number, depth: $depth)';
}


}

/// @nodoc
abstract mixin class $BlockKind_ListItemCopyWith<$Res> implements $BlockKindCopyWith<$Res> {
  factory $BlockKind_ListItemCopyWith(BlockKind_ListItem value, $Res Function(BlockKind_ListItem) _then) = _$BlockKind_ListItemCopyWithImpl;
@useResult
$Res call({
 int? number, int depth
});




}
/// @nodoc
class _$BlockKind_ListItemCopyWithImpl<$Res>
    implements $BlockKind_ListItemCopyWith<$Res> {
  _$BlockKind_ListItemCopyWithImpl(this._self, this._then);

  final BlockKind_ListItem _self;
  final $Res Function(BlockKind_ListItem) _then;

/// Create a copy of BlockKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? number = freezed,Object? depth = null,}) {
  return _then(BlockKind_ListItem(
number: freezed == number ? _self.number : number // ignore: cast_nullable_to_non_nullable
as int?,depth: null == depth ? _self.depth : depth // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BlockKind_Code extends BlockKind {
  const BlockKind_Code({this.language}): super._();
  

 final  String? language;

/// Create a copy of BlockKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockKind_CodeCopyWith<BlockKind_Code> get copyWith => _$BlockKind_CodeCopyWithImpl<BlockKind_Code>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockKind_Code&&(identical(other.language, language) || other.language == language));
}


@override
int get hashCode {
    return Object.hash(runtimeType,language);
}

@override
String toString() {
    return 'BlockKind.code(language: $language)';
}


}

/// @nodoc
abstract mixin class $BlockKind_CodeCopyWith<$Res> implements $BlockKindCopyWith<$Res> {
  factory $BlockKind_CodeCopyWith(BlockKind_Code value, $Res Function(BlockKind_Code) _then) = _$BlockKind_CodeCopyWithImpl;
@useResult
$Res call({
 String? language
});




}
/// @nodoc
class _$BlockKind_CodeCopyWithImpl<$Res>
    implements $BlockKind_CodeCopyWith<$Res> {
  _$BlockKind_CodeCopyWithImpl(this._self, this._then);

  final BlockKind_Code _self;
  final $Res Function(BlockKind_Code) _then;

/// Create a copy of BlockKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? language = freezed,}) {
  return _then(BlockKind_Code(
language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BlockKind_Rule extends BlockKind {
  const BlockKind_Rule(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockKind_Rule);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BlockKind.rule()';
}


}




// dart format on
