pub const Error = error{
    UnsupportedInstruction,
    PrologueTooShort,
    OutOfExecutableMemory,
    ProtectFailed,
    AlreadyEnabled,
    NotEnabled,
};
