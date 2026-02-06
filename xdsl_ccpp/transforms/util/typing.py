from xdsl.dialects import builtin, memref

class TypeConversions():
    TEXT_TYPE_TO_MLIR_TYPE={"character":builtin.i8, "integer":builtin.i32, "real":builtin.f64}
    
    @classmethod
    def convert(cls, text_type, kind=None):                        
        base_type=cls.getBaseType(text_type)
        shape=[]
        if kind is not None:
            if "len=" in kind:
                shape=[int(kind.split("=")[1])]
        return memref.MemRefType(base_type, shape)
        
    @classmethod
    def getBaseType(cls, text_type):
        assert text_type in cls.TEXT_TYPE_TO_MLIR_TYPE.keys()        
        return cls.TEXT_TYPE_TO_MLIR_TYPE[text_type]
    

