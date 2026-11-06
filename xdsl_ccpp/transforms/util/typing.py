from xdsl.dialects import builtin, func, memref
from xdsl.dialects.builtin import DYNAMIC_INDEX

from xdsl_ccpp.dialects.ccpp_utils import DerivedType, RealKindType


class TypeConversions:
    """Utility class that maps CCPP metadata type strings to xDSL/MLIR types.

    CCPP ``.meta`` files describe argument types using plain strings (e.g.
    ``type = real``) with an optional ``kind`` qualifier (e.g.
    ``kind = len=512`` for a fixed-length character array) and an optional
    dimension count derived from the ``dimensions`` tuple.

    This class centralises the conversion of those strings into concrete MLIR
    types so that the rest of the pipeline can work with typed IR from the
    start.

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

    The ``kind`` qualifier is used for ``character`` to specify the string
    length via ``len=<N>``, producing a ranked ``memref<N x i8>``.

    The ``dimensions`` count is used for array arguments: each dimension
    becomes a ``DYNAMIC_INDEX`` (``?``) entry in the memref shape, producing
    e.g. ``memref<?x?xf64>`` for a 2-D real array.  The actual extents are
    not known at compile time — they are supplied by the host model at runtime
    through Fortran's assumed-shape array mechanism.
    """

    # Mapping from CCPP metadata type string → MLIR scalar type
    TEXT_TYPE_TO_MLIR_TYPE = {
        "character": builtin.i8,
        "integer": builtin.i32,
        "real": builtin.f64,
        "logical": builtin.i1,
    }

    # Derived types that the CCPP framework provides, with no metadata of their own
    FRAMEWORK_DDTS = {
        "ccpp_constituent_properties_t": "ccpp_constituent_prop_mod",
        "ccpp_constituent_prop_ptr_t": "ccpp_constituent_prop_mod",
        "ccpp_model_constituents_t": "ccpp_constituent_prop_mod",
    }

    @classmethod
    def convert(cls, text_type, kind=None, dimensions=0):
        """Convert a CCPP type string (and optional kind/dimensions) to a `memref` MLIR type.

        Args:
            text_type: CCPP type string, one of ``"character"``, ``"integer"``,
                       or ``"real"``.
            kind: Optional kind qualifier string from the ``.meta`` file.
                  Only ``"len=<N>"`` is handled, producing a ``memref<N x i8>``
                  for fixed-length character strings.
            dimensions: Number of array dimensions (0 = scalar).  For each
                        dimension a ``DYNAMIC_INDEX`` (``?``) entry is added to
                        the memref shape, producing e.g. ``memref<?x?xf64>``.

        Returns:
            A `memref.MemRefType` with:

            - Shape ``[N]`` if ``kind = "len=N"`` (fixed-length character array).
            - Shape ``[?, ?, ...]`` with ``dimensions`` entries if ``dimensions > 0``.
            - Shape ``[]`` (zero-dimensional scalar memref) otherwise.
        """
        shape = []
        if text_type == "real" and kind is not None and "len=" not in kind:
            # Named kind qualifier (e.g. kind_phys) — use RealKindType to carry
            # the kind name through the IR for Fortran code generation.
            base_type = RealKindType(kind)
        else:
            base_type = cls.getBaseType(text_type)
        if kind is not None and "len=" in kind:
            # A 'len=N' kind qualifier on a character type sets the string length.
            # 'len=*' means assumed-length (dynamic); any integer N means fixed length.
            # Other kind values (e.g. 'kind_phys') are Fortran precision specifiers
            # and have no effect on the memref shape.
            len_val = kind.split("=")[1]
            shape = [DYNAMIC_INDEX if len_val == "*" else int(len_val)]
            # For a character array the leading memref dimension is the string
            # length and the array dimensions follow it.
            shape += [DYNAMIC_INDEX] * dimensions
        elif text_type == "character" and dimensions > 0:
            shape = [1] + [DYNAMIC_INDEX] * dimensions
        elif dimensions > 0:
            # Each CCPP dimension maps to a dynamic-size axis in the memref;
            # the actual extent is provided by the host at runtime
            shape = [DYNAMIC_INDEX] * dimensions
        return memref.MemRefType(base_type, shape)

    @classmethod
    def convert_arg(cls, arg, dimensions=None):
        """Convert a metadata argument to its type.

        *dimensions* overrides the rank, for a selection from a larger array.
        """
        if dimensions is None:
            dimensions = arg.getAttr("dimensions") if arg.hasAttr("dimensions") else 0
        kind = arg.getAttr("kind") if arg.hasAttr("kind") else None
        return cls.convert(arg.getAttr("type"), kind, dimensions)

    @classmethod
    def derived_type_uses(cls, module_op, meta_data):
        """Return ``{ddt_name: fortran_module}`` for the DDTs used in *module_op*.

        Only DDTs whose defining module is known from the metadata are included.
        """
        seen = set()
        for op in module_op.walk():
            types = [res.type for res in op.results]
            if isinstance(op, func.FuncOp):
                types += [*op.function_type.inputs, *op.function_type.outputs]
            for type_attr in types:
                if isinstance(type_attr, memref.MemRefType):
                    type_attr = type_attr.element_type
                if isinstance(type_attr, DerivedType):
                    seen.add(type_attr.type_name.data)
        modules = dict(cls.FRAMEWORK_DDTS)
        for name, props in meta_data.items():
            if props.hasAttr("module"):
                modules[name] = props.getAttr("module")
        return {name: modules[name] for name in sorted(seen) if name in modules}

    @classmethod
    def getBaseType(cls, text_type):
        """Return the MLIR scalar type for a CCPP type string.

        Args:
            text_type: One of ``"character"``, ``"integer"``, ``"real"``, or a
                       Fortran derived-type name (e.g. ``"vmr_type"``).

        Returns:
            The corresponding xDSL builtin type (``i8``, ``i32``, or ``f64``),
            or a `DerivedType` for unknown types representing Fortran DDTs.
        """
        if text_type in cls.TEXT_TYPE_TO_MLIR_TYPE:
            return cls.TEXT_TYPE_TO_MLIR_TYPE[text_type]
        return DerivedType(text_type)
