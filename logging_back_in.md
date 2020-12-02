# If you get logged out

If you get logged out, you’ll need to log back into the control cluster and each of the three regional clusters.

## First, log into the "ctrl" cluster's UI and get a token to use for logging in via CLI.

Use the details in these INFO lines to log in:

```
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/Users/mgoddard/RedHat/os-aws/auth/kubeconfig' 
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.ctrl.your-domain.com 
INFO Login to the console with user: "kubeadmin", and password: "28ywz-AKdri-r8iXi-Qabc"
```

Once logged in there, you can click on the "kube:admin" button in the upper right of the UI and,
from there, click "Copy Login Command" to open a new browser tab.  Then, click "Display Token"
to see the actual login command.

Use that token to log in using the `oc` CLI:
```
oc login --token=EjZen[...]7klq --server=https://api.ctrl.your-domain.com:6443
```

Which outputs:

```
Logged into "https://api.ctrl.your-domain.com:6443" as "kube:admin" using the token provided.

You have access to 65 projects, the list has been suppressed. You can list all projects with 'oc projects'

Using project "default".
```

To ensure you're using the correct project, you can run
```
oc project  default
```

