#!/bin/bash

# Define the AppsDirectory variable
AppsDirectory="$TC/bootstrap/templates/kubernetes/apps/"
SelectedNamespace=""
AppName=""
ChartName="app-template"  # Default ChartName
RepoName="bjw-s"          # Default RepoName

# Variables to track if user wants Ingress or Secrets templates
ingress_required="no"
secrets_required="no"
OCI="no"
RepoUrl=""

# Function to ask for ChartName and RepoName
ask_for_chart_and_repo() {
    # Ask for ChartName (default is "app-template")
    read -p "Enter the ChartName (default: app-template): " input_chartname
    ChartName="${input_chartname:-$ChartName}"

    # Ask for RepoName (default is "bjw-s")
    read -p "Enter the RepoName (default: bjw-s): " input_reponame
    RepoName="${input_reponame:-$RepoName}"

    # Check if the $RepoName.yaml.j2 file exists
    repo_file="/home/knightdoom/control/taloscluster/bootstrap/templates/kubernetes/flux/repositories/helm/$RepoName.yaml.j2"
    if [ ! -f "$repo_file" ]; then
        echo "$RepoName.yaml.j2 does not exist."
        
        # Ask if the repository type is OCI
        read -p "Is the repository OCI? (yes/no): " OCI
        if [[ "$OCI" == "yes" ]]; then
            # Ask for the OCI Repo URL
            read -p "Enter the OCI repository URL: " RepoUrl
        fi
        
        # Create the HelmRepository YAML file
        echo "Creating $RepoName.yaml.j2"
        cat > "$repo_file" <<EOF
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: $RepoName
  namespace: flux-system
spec:
  $(if [[ "$OCI" == "yes" ]]; then echo "  type: oci"; fi)
  interval: 5m
  url: $RepoUrl
EOF
        echo "$RepoName.yaml.j2 file created."

        # Append the new repository to kustomization.yaml.j2 if the file doesn't already have it
        kustomization_file="/home/knightdoom/control/taloscluster/bootstrap/templates/kubernetes/flux/repositories/helm/kustomization.yaml.j2"
        if ! grep -q "$RepoName.yaml" "$kustomization_file"; then
            echo "Appending repository reference to $kustomization_file"
            echo "  - ./$RepoName.yaml" >> "$kustomization_file"
            echo "Repository reference appended to kustomization.yaml.j2."
        else
            echo "Repository reference already exists in $kustomization_file."
        fi
    else
        echo "$RepoName.yaml.j2 already exists."
    fi
}

# Function to display options and handle selection
select_namespace() {
    directories=$(find "$AppsDirectory" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
    options="$directories new_namespace"
    
    echo "Select a namespace:"
    select namespace in $options; do
        case $namespace in
            "new_namespace")
                echo "You selected to create a new namespace."
                # Ask for the new namespace name
                read -p "Enter the new namespace name: " namespace_name

                # Check if the namespace directory already exists
                new_namespace_dir="$AppsDirectory/$namespace_name"
                if [ -d "$new_namespace_dir" ]; then
                    echo "The namespace '$namespace_name' already exists. Please choose a different name."
                    continue
                fi
                
                # Create the new folder for the namespace
                echo "Creating new namespace folder: $new_namespace_dir"
                mkdir -p "$new_namespace_dir"
                echo "Namespace folder created."

                # Create the namespace.yaml.j2 file
                echo "Creating namespace.yaml.j2 file in $new_namespace_dir"
                cat > "$new_namespace_dir/namespace.yaml.j2" <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace_name
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
EOF
                echo "namespace.yaml.j2 file created."

                # Create the kustomization.yaml.j2 file
                echo "Creating kustomization.yaml.j2 file in $new_namespace_dir"
                cat > "$new_namespace_dir/kustomization.yaml.j2" <<EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
EOF
                echo "kustomization.yaml.j2 file created."

                # Update the global variable with the newly created namespace
                SelectedNamespace="$namespace_name"
                break
                ;;

            # Handle existing namespace selection
            *)
                echo "You selected an existing namespace: $namespace"
                # Ensure the selected directory exists
                if [ -d "$AppsDirectory/$namespace" ]; then
                    # Update the global variable with the selected namespace
                    SelectedNamespace="$namespace"
                    break
                else
                    echo "Invalid selection, try again."
                fi
                ;;
        esac
    done
}

# Function to handle AppName and its operations
create_app() {
    # Ask for the AppName
    echo "You selected namespace '$SelectedNamespace'. Now, please enter the AppName."
    read -p "Enter the AppName: " AppName

    # Check if the AppName directory exists
    app_dir="$AppsDirectory/$SelectedNamespace/$AppName"
    if [ -d "$app_dir" ]; then
        echo "The application '$AppName' already exists in namespace '$SelectedNamespace'."
        return
    fi
    # Ask for the PortNum`
    echo "You selected namespace '$SelectedNamespace'. Now, please enter the port for '$AppName'."
    read -p "Enter the Port Number: " PortNum
    # Create the app directory
    echo "Creating new application folder: $app_dir"
    mkdir -p "$app_dir"
    echo "Application folder created."

    # Append ks.yaml path to kustomization.yaml.j2 if it exists
    kustomization_file="$AppsDirectory/$SelectedNamespace/kustomization.yaml.j2"
    if [ -f "$kustomization_file" ]; then
        echo "Appending - ./$AppName/ks.yaml to $kustomization_file"
        echo -e "\n  - ./$AppName/ks.yaml" >> "$kustomization_file"
        echo "App path added to kustomization.yaml.j2."
    
        # Remove empty lines from the kustomization.yaml.j2 file
        echo "Removing empty lines from $kustomization_file"
        sed -i '/^$/d' "$kustomization_file"
        echo "Empty lines removed from $kustomization_file."
    fi

    # Create ks.yaml.j2 with the specific content
    echo "Creating ks.yaml.j2 file in $app_dir"
    cat > "$app_dir/ks.yaml.j2" <<EOF
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app $AppName
  namespace: flux-system
spec:
  targetNamespace: $SelectedNamespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/apps/$SelectedNamespace/$AppName/app
  prune: false
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
  wait: false
  interval: 30m
  timeout: 5m
EOF
    echo "ks.yaml.j2 file created."

    # Create the app folder inside the app directory
    app_subdir="$app_dir/app"
    echo "Creating app sub-directory: $app_subdir"
    mkdir -p "$app_subdir"
    echo "App sub-directory created."

    # Create helmrelease.yaml.j2 inside the app folder with the specific content
    echo "Creating helmrelease.yaml.j2 file in $app_subdir"
    cat > "$app_subdir/helmrelease.yaml.j2" <<EOF
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $AppName
spec:
  interval: 30m
  chart:
    spec:
      chart: $ChartName
     # version: 4.1.1
      sourceRef:
        kind: HelmRepository
        name: $RepoName
        namespace: flux-system
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
#  valuesFrom:
#   - kind: ConfigMap
#     name: $AppName-helm-values
  values: 
     #enter values here for global overrides  
    controllers:
      $AppName:
        annotations:
          reloader.stakater.com/auto: "true"
        # initContainers:
          # init-db:
            # image:
              # repository: ghcr.io/onedr0p/postgres-init
              # tag: 16
            # envFrom: &envFrom
              # - secretRef:
                  # name: radarr-secret
        containers:
          app:
            image:
              repository: ghcr.io/onedr0p/radarr-develop
              tag: 5.17.0.9555@sha256:ca1d1f55524c1d58cd9aa58e747b7ee37536aed4f95852ab07eb0b984dcf1817
            env:
              # RADARR__APP__INSTANCENAME: Radarr
              # RADARR__APP__THEME: dark
              portNum: &port $PortNum
              TZ: America/New_York
            # envFrom: *envFrom
            probes:
              liveness: &probes
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /health
                    port: *port
                  initialDelaySeconds: 15
                  periodSeconds: 10
                  timeoutSeconds: 1
                  failureThreshold: 3
              readiness: *probes
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities: { drop: ["ALL"] }
            resources:
              requests:
                cpu: 100m
                memory: 100Mi
              limits:
                memory: 4Gi
    defaultPodOptions:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile: { type: RuntimeDefault }
    service:
      app:
        controller: $AppName
        ports:
          http:
            port: *port
    ingress:
      app:
        className: internal
        #annotations:
        # - nginx.ingress.kubernetes.io/app-root: /$AppName
        hosts:
          - host: "{{ .Release.Name }}.knightd.win"
            paths:
              - path: /
                service:
                  identifier: app
                  port: http
    persistence:
      config:
        existingClaim: $AppName
      # scripts:
        # type: configMap
        # name: radarr-configmap
        # defaultMode: 0775
        # globalMounts:
          # - path: /scripts/pushover-notifier.sh
            # subPath: pushover-notifier.sh
            # readOnly: true
      tmp:
        type: emptyDir
        globalMounts:
          - path: /tmp
      media:
        type: nfs
        server: 192.168.86.9
        path: /PlexLib
        globalMounts:
          - path: /library

EOF
    echo "helmrelease.yaml.j2 file created."

    # Ask the user if they require a separate Ingress template
    read -p "Do you require a separate ingress template? (yes/no): " ingress_required
    if [[ "$ingress_required" == "yes" ]]; then
        echo "Creating ingress.yaml.j2 file in $app_subdir"
        cat > "$app_subdir/ingress.yaml.j2" <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $AppName-ingress 
  namespace: $SelectedNamespace 
  #annotations:
    #external-dns.alpha.kubernetes.io/target: "$AppName.\$\{SECRET_DOMAIN\}" 
spec:
  ingressClassName: internal #external or internal 
  rules:
    - host: "$AppName.\$\{SECRET_DOMAIN}" 
      http:
        paths:
          - path: / 
            pathType: Prefix
            backend:
              service:
                name: $AppName #May need to change this
                port:
                  number: 80
EOF
        echo "ingress.yaml.j2 file created."
    fi

    # Ask the user if they require a Secrets template
    read -p "Do you require a secrets template? (yes/no): " secrets_required
    if [[ "$secrets_required" == "yes" ]]; then
        echo "Creating secret.sops.yaml.j2 file in $app_subdir"
        cat > "$app_subdir/secret.sops.yaml.j2" <<EOF
# file name should use secret.sops.yaml.j2
# use below example refer to it
 # env:
      # - name: CF_API_TOKEN
        # valueFrom:
          # secretKeyRef:
            # name: external-dns-secret
            # key: api-token
          
# ---
# apiVersion: v1
# kind: Secret
# metadata:
  # name: external-dns-secret
# stringData:
  # api-token: "#{ bootstrap_cloudflare.token }#"
EOF
        echo "secret.sops.yaml.j2 file created."
    fi

    # Create helm-values.yaml.j2 file
#    echo "Creating helm-values.yaml.j2 file in $app_subdir"
#    cat > "$app_subdir/helm-values.yaml.j2" <<EOF
##fill here with helm values for chart
#EOF
#    echo "helm-values.yaml.j2 file created."

#    # Create kustomizeconfig.yaml.j2 file
#    echo "Creating kustomizeconfig.yaml.j2 file in $app_subdir"
#    cat > "$app_subdir/kustomizeconfig.yaml.j2" <<EOF
#---
#nameReference:
#  - kind: ConfigMap
#    version: v1
#    fieldSpecs:
#      - path: spec/valuesFrom/name
#        kind: HelmRelease
#EOF
#    echo "kustomizeconfig.yaml.j2 file created."

    # Create kustomization.yaml.j2 with conditional resource inclusion
    echo "Creating kustomization.yaml.j2 file in $app_subdir"
    cat > "$app_subdir/kustomization.yaml.j2" <<EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # Include ingress.yaml only if required
  $(if [[ "$ingress_required" == "yes" ]]; then echo "- ./ingress.yaml"; fi)
  # Include secret.sops.yaml only if required
  $(if [[ "$secrets_required" == "yes" ]]; then echo "- ./secret.sops.yaml"; fi)
  - ./helmrelease.yaml
#configMapGenerator:
#  - name: $AppName-helm-values
#    files:
#      - values.yaml=./helm-values.yaml
#configurations:
#  - kustomizeconfig.yaml
generatorOptions:
  disableNameSuffixHash: true
EOF
    echo "kustomization.yaml.j2 file created."

    echo "Application '$AppName' created in namespace '$SelectedNamespace'."
}

# Start by asking for chart and repo information
ask_for_chart_and_repo

# Call the function to select namespace
select_namespace

# Final output
echo "The selected namespace is: $SelectedNamespace"

# Call the function to create the app
create_app


##!/bin/bash
#
## Define the AppsDirectory variable
#AppsDirectory="$TC/bootstrap/templates/kubernetes/apps/"
#SelectedNamespace=""
#AppName=""
#ChartName="your-chart-name"  # Set default chart name or let the user input it later
#RepoName="your-repo-name"    # Set default repository name or let the user input it later
#
## Function to display options and handle selection
#select_namespace() {
#    # Get the list of directories in AppsDirectory
#    directories=$(find "$AppsDirectory" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
#
#    # Prepare the options for select (existing directories and the "new namespace" option)
#    options="$directories new_namespace"
#    
#    # Display the menu and get selection
#    echo "Select a namespace:"
#    select namespace in $options; do
#        case $namespace in
#            # Handle new namespace creation
#            "new_namespace")
#                echo "You selected to create a new namespace."
#                # Ask for the new namespace name
#                read -p "Enter the new namespace name: " namespace_name
#
#                # Check if the namespace directory already exists
#                new_namespace_dir="$AppsDirectory/$namespace_name"
#                if [ -d "$new_namespace_dir" ]; then
#                    echo "The namespace '$namespace_name' already exists. Please choose a different name."
#                    continue
#                fi
#                
#                # Create the new folder for the namespace
#                echo "Creating new namespace folder: $new_namespace_dir"
#                mkdir -p "$new_namespace_dir"
#                echo "Namespace folder created."
#
#                # Create the namespace.yaml.j2 file
#                echo "Creating namespace.yaml.j2 file in $new_namespace_dir"
#                cat > "$new_namespace_dir/namespace.yaml.j2" <<EOF
#---
#apiVersion: v1
#kind: Namespace
#metadata:
#  name: $namespace_name
#  labels:
#    kustomize.toolkit.fluxcd.io/prune: disabled
#EOF
#                echo "namespace.yaml.j2 file created."
#
#                # Create the kustomization.yaml.j2 file
#                echo "Creating kustomization.yaml.j2 file in $new_namespace_dir"
#                cat > "$new_namespace_dir/kustomization.yaml.j2" <<EOF
#---
#apiVersion: kustomize.config.k8s.io/v1beta1
#kind: Kustomization
#resources:
#  - ./namespace.yaml
#EOF
#                echo "kustomization.yaml.j2 file created."
#
#                # Update the global variable with the newly created namespace
#                SelectedNamespace="$namespace_name"
#                break
#                ;;
#            
#            # Handle existing namespace selection
#            *)
#                echo "You selected an existing namespace: $namespace"
#                # Ensure the selected directory exists
#                if [ -d "$AppsDirectory/$namespace" ]; then
#                    # Update the global variable with the selected namespace
#                    SelectedNamespace="$namespace"
#                    break
#                else
#                    echo "Invalid selection, try again."
#                fi
#                ;;
#        esac
#    done
#}
#
## Function to handle AppName and its operations
#create_app() {
#    # Ask for the AppName
#    echo "You selected namespace '$SelectedNamespace'. Now, please enter the AppName."
#    read -p "Enter the AppName: " AppName
#
#    # Check if the AppName directory exists
#    app_dir="$AppsDirectory/$SelectedNamespace/$AppName"
#    if [ -d "$app_dir" ]; then
#        echo "The application '$AppName' already exists in namespace '$SelectedNamespace'."
#        return
#    fi
#
#    # Create the app directory
#    echo "Creating new application folder: $app_dir"
#    mkdir -p "$app_dir"
#    echo "Application folder created."
#
#    # Append ks.yaml path to kustomization.yaml.j2 if it exists
#    kustomization_file="$AppsDirectory/$SelectedNamespace/kustomization.yaml.j2"
#    if [ -f "$kustomization_file" ]; then
#        echo "Appending - ./$AppName/ks.yaml to $kustomization_file"
#        echo -e "\n  - ./$AppName/ks.yaml" >> "$kustomization_file"
#        echo "App path added to kustomization.yaml.j2."
#    
#        # Remove empty lines from the kustomization.yaml.j2 file
#        echo "Removing empty lines from $kustomization_file"
#        sed -i '/^$/d' "$kustomization_file"
#        echo "Empty lines removed from $kustomization_file."
#    fi
#
#
#    # Create ks.yaml.j2 with the specific content
#    echo "Creating ks.yaml.j2 file in $app_dir"
#    cat > "$app_dir/ks.yaml.j2" <<EOF
#---
#apiVersion: kustomize.toolkit.fluxcd.io/v1
#kind: Kustomization
#metadata:
#  name: &app $AppName 
#  namespace: flux-system
#spec:
#  targetNamespace: $SelectedNamespace
#  commonMetadata:
#    labels:
#      app.kubernetes.io/name: *app
#  path: ./kubernetes/apps/$SelectedNamespace/$AppName/app
#  prune: false
#  sourceRef:
#    kind: GitRepository
#    name: home-kubernetes
#  wait: false
#  interval: 30m
#  timeout: 5m
#EOF
#    echo "ks.yaml.j2 file created."
#
#    # Create the app folder inside the app directory
#    app_subdir="$app_dir/app"
#    echo "Creating app sub-directory: $app_subdir"
#    mkdir -p "$app_subdir"
#    echo "App sub-directory created."
#
#    # Create helmrelease.yaml.j2 inside the app folder with the specific content
#    echo "Creating helmrelease.yaml.j2 file in $app_subdir"
#    cat > "$app_subdir/helmrelease.yaml.j2" <<EOF
#---
#apiVersion: helm.toolkit.fluxcd.io/v2
#kind: HelmRelease
#metadata:
#  name: $AppName
#spec:
#  interval: 30m
#  chart:
#    spec:
#      chart: $ChartName
#     # version: 4.1.1
#      sourceRef:
#        kind: HelmRepository
#        name: $RepoName
#        namespace: flux-system
#  install:
#    remediation:
#      retries: 3
#  upgrade:
#    cleanupOnFail: true
#    remediation:
#      retries: 3
#  valuesFrom:
#   - kind: ConfigMap
#     name: $AppName-helm-values
##  values: 
##     #enter values here for global overrides  
#EOF
#    echo "helmrelease.yaml.j2 file created."
#
#    echo "Application '$AppName' created in namespace '$SelectedNamespace'."
#}
#
## Call the function to select namespace
#select_namespace
#
## Final output
#echo "The selected namespace is: $SelectedNamespace"
#
## Call the function to create the app
#create_app
#
