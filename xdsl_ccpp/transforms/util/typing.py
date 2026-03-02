from xdsl.dialects import builtin, memref


class TypeConversions():
    """Utility class that maps CCPP metadata type strings to xDSL/MLIR types.

    CCPP ``.meta`` files describe argument types using plain strings (e.g.
    ``type = real``) with an optional ``kind`` qualifier (e.g.
    ``kind = len=512`` for a fixed-length character array).  This class
    centralises the conversion of those strings into concrete MLIR types so
    that the rest of the pipeline can work with typed IR from the start.

    All methods are class methods — the class is never instantiated.

    Type mapping
    ------------
    ============  ===========  ======================================
    CCPP type     MLIR base    Notes
    ============  ===========  ======================================
    ``character`` ``i8``       Each character is one byte
    ``integer``   ``i32``      Default Fortran integer width
    ``real``      ``f64``      Default Fortran double precision
    ============  ===========  ======================================

    The ``kind`` qualifier is currently used only for ``character`` to specify
    the string length via ``len=<N>``, which produces a ranked ``memref<N x i8>``.
    For all other types (or when ``kind`` is absent) a zero-dimensional
    ``memref<base_type>`` is returned, which the Fortran printer treats as a
    plain scalar.
    """

    # Mapping from CCPP metadata type string → MLIR scalar type
    TEXT_TYPE_TO_MLIR_TYPE = {
        "character": builtin.i8,
        "integer": builtin.i32,
        "real": builtin.f64,
    }

    @classmethod
    def convert(cls, text_type, kind=None):
        """Convert a CCPP type string (and optional kind) to a `memref` MLIR type.

        Args:
            text_type: CCPP type string, one of ``"character"``, ``"integer"``,
                       or ``"real"``.
            kind: Optional kind qualifier string from the ``.meta`` file.
                  Currently only ``"len=<N>"`` is handled, which sets the memref
                  shape to ``[N]`` for character arrays.

        Returns:
            A `memref.MemRefType` with:

            - Shape ``[N]`` if ``kind = "len=N"`` (ranked character array).
            - Shape ``[]`` (zero-dimensional scalar memref) otherwise.
        """
        base_type = cls.getBaseType(text_type)
        shape = []
        if kind is not None:
            # A 'len=N' kind qualifier means a fixed-length character array
            if "len=" in kind:
                shape = [int(kind.split("=")[1])]
        return memref.MemRefType(base_type, shape)

    @classmethod
    def getBaseType(cls, text_type):
        """Return the MLIR scalar type for a CCPP type string.

        Args:
            text_type: One of ``"character"``, ``"integer"``, or ``"real"``.

        Returns:
            The corresponding xDSL builtin type (``i8``, ``i32``, or ``f64``).
        """
        assert text_type in cls.TEXT_TYPE_TO_MLIR_TYPE.keys()
        return cls.TEXT_TYPE_TO_MLIR_TYPE[text_type]
