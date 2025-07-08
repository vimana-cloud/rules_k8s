K8sResources = provider(
    "A collection of Kubernetes resources defined by a set of JSON or YAML files.",
    fields = {
        "files": "Dependency set of file objects representing the resources.",
    },
)

SetupActions = provider(
    "A collection of executable actions and their associated runfiles." +
    " These actions are intended to run while setting up a cluster.",
    fields = {
        "executables": "Dependency set of executable file objects.",
        "runfiles": "Merged runfiles of all the executables.",
    },
)
