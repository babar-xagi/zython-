const std = @import("std");
const value_mod = @import("value.zig");
const Value = value_mod.Value;

pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    floor_div,
    mod,
    pow,
    bit_and,
    bit_or,
    bit_xor,
    lshift,
    rshift,
};

pub const UnaryOp = enum {
    plus,
    minus,
    invert,
    not,
};

pub const CompareOp = enum {
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    in,
    not_in,
    is,
    is_not,
};

pub const BoolOp = enum {
    op_and,
    op_or,
};

pub const Kwarg = struct {
    name: []const u8,
    value: *Expr,
};

pub const SliceExpr = struct {
    lower: ?*Expr,
    upper: ?*Expr,
    step: ?*Expr,
    is_index: bool,
};

pub const ListComp = struct {
    elt: *Expr,
    target: *Expr,
    iter: *Expr,
    condition: ?*Expr,
};

pub const FString = struct {
    parts: []*Expr,
};

pub const IdentExpr = struct {
    name: []const u8,
    slot_idx: u8 = 255,
    cached_val: ?Value = null,
};

pub const Expr = union(enum) {
    literal: Value,
    identifier: IdentExpr,
    binary: struct { left: *Expr, op: BinaryOp, right: *Expr },
    unary: struct { op: UnaryOp, expr: *Expr },
    compare: struct { left: *Expr, ops: []CompareOp, rights: []*Expr },
    bool_op: struct { op: BoolOp, values: []*Expr },
    call: struct { callee: *Expr, args: []*Expr, kwargs: []Kwarg },
    attribute: struct {
        value: *Expr,
        attr: []const u8,
        cached_class: ?*anyopaque = null,
        cached_method: ?Value = null,
        cached_slot: u8 = 255,
    },
    subscript: struct { value: *Expr, slice: *SliceExpr },
    list_expr: []*Expr,
    tuple_expr: []*Expr,
    dict_expr: struct { keys: []*Expr, values: []*Expr },
    set_expr: []*Expr,
    ternary: struct { if_val: *Expr, condition: *Expr, else_val: *Expr },
    lambda: struct { params: [][]const u8, body: *Expr },
    list_comp: ListComp,
    f_string: FString,
    yield_expr: ?*Expr,
    await_expr: *Expr,
};

pub const Param = struct {
    name: []const u8,
    default: ?*Expr,
    is_vararg: bool,
    is_kwarg: bool,
};

pub const ElifBranch = struct {
    condition: *Expr,
    body: []Stmt,
};

pub const ExceptHandler = struct {
    exc_type: ?*Expr,
    name: ?[]const u8,
    body: []Stmt,
};

pub const Stmt = union(enum) {
    assign: struct { targets: []*Expr, value: *Expr },
    aug_assign: struct { target: *Expr, op: BinaryOp, value: *Expr },
    expr_stmt: *Expr,
    if_stmt: struct {
        condition: *Expr,
        then_branch: []Stmt,
        elif_branches: []ElifBranch,
        else_branch: ?[]Stmt,
    },
    while_stmt: struct {
        condition: *Expr,
        body: []Stmt,
        else_branch: ?[]Stmt,
    },
    for_stmt: struct {
        target: *Expr,
        iter: *Expr,
        body: []Stmt,
        else_branch: ?[]Stmt,
    },
    def_stmt: struct {
        name: []const u8,
        params: []Param,
        body: []Stmt,
        decorators: []*Expr = &.{},
        is_async: bool = false,
    },
    with_stmt: struct {
        context_expr: *Expr,
        optional_vars: ?*Expr,
        body: []Stmt,
    },
    class_stmt: struct {
        name: []const u8,
        bases: []*Expr,
        body: []Stmt,
    },
    return_stmt: ?*Expr,
    break_stmt,
    continue_stmt,
    pass_stmt,
    try_stmt: struct {
        body: []Stmt,
        handlers: []ExceptHandler,
        else_branch: ?[]Stmt,
        finally_branch: ?[]Stmt,
    },
    raise_stmt: ?*Expr,
    import_stmt: struct {
        module_name: []const u8,
        as_name: ?[]const u8,
    },
    import_from_stmt: struct {
        module_name: []const u8,
        names: [][]const u8,
        as_names: []?[]const u8,
    },
    global_stmt: [][]const u8,
    assert_stmt: struct {
        condition: *Expr,
        message: ?*Expr,
    },
};
