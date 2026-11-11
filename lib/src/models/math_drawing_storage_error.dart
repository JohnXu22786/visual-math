/// Duplicate document names require an explicit overwrite decision.
class DuplicateDrawingException extends StateError {
  DuplicateDrawingException(String name)
    : super(
        'A drawing named "$name" already exists. Choose another name or confirm overwrite.',
      );
}
