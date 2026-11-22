#include <stdint.h>
#include <stddef.h>

typedef struct _object {
    int64_t ob_refcnt;
    void *ob_type;
} PyObject;

typedef PyObject *(*PyCFunction)(PyObject *, PyObject *);

typedef struct PyMethodDef {
    const char  *ml_name;
    PyCFunction ml_meth;
    int         ml_flags;
    const char  *ml_doc;
} PyMethodDef;

typedef struct PyModuleDef_Base {
    PyObject ob_base;
    PyObject *(*m_init)(void);
    int64_t m_index;
    PyObject *m_copy;
} PyModuleDef_Base;

typedef struct PyModuleDef {
    PyModuleDef_Base m_base;
    const char* m_name;
    const char* m_doc;
    int64_t m_size;
    PyMethodDef *m_methods;
} PyModuleDef;

typedef struct {
    PyObject ob_base;
    PyModuleDef *def;
    const char *name;
} PyModuleObject;

#define METH_VARARGS 0x0001
#define METH_NOARGS  0x0004
#define METH_O       0x0008

// Standard CPython C-API functions exported by Zython runtime
extern PyObject* PyLong_FromLong(long v);
extern long PyLong_AsLong(PyObject *obj);
extern PyObject* PyFloat_FromDouble(double v);
extern double PyFloat_AsDouble(PyObject *obj);
extern PyObject* PyTuple_GetItem(PyObject *p, int64_t pos);
extern int64_t PyTuple_Size(PyObject *p);

static PyObject* ext_add(PyObject *self, PyObject *args) {
    (void)self;
    PyObject *item0 = PyTuple_GetItem(args, 0);
    PyObject *item1 = PyTuple_GetItem(args, 1);
    long a = PyLong_AsLong(item0);
    long b = PyLong_AsLong(item1);
    return PyLong_FromLong(a + b);
}

static PyObject* ext_multiply(PyObject *self, PyObject *args) {
    (void)self;
    PyObject *item0 = PyTuple_GetItem(args, 0);
    PyObject *item1 = PyTuple_GetItem(args, 1);
    double a = PyFloat_AsDouble(item0);
    double b = PyFloat_AsDouble(item1);
    return PyFloat_FromDouble(a * b);
}

static PyMethodDef SampleMethods[] = {
    {"add", ext_add, METH_VARARGS, "Add two integers"},
    {"multiply", ext_multiply, METH_VARARGS, "Multiply two floats"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef sample_module = {
    {{1, NULL}, NULL, 0, NULL},
    "sample_ext",
    "Sample C extension for Zython",
    -1,
    SampleMethods
};

static PyModuleObject sample_mod_obj;

PyObject* PyInit_sample_ext(void) {
    sample_mod_obj.ob_base.ob_refcnt = 1;
    sample_mod_obj.ob_base.ob_type = (void*)7;
    sample_mod_obj.def = &sample_module;
    sample_mod_obj.name = "sample_ext";
    return (PyObject*)&sample_mod_obj;
}
