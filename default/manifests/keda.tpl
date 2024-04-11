apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: azure-servicebus-auth
  namespace: default
spec:
  podIdentity:
    provider: azure
---
# dispatch
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: servicebus-dispatcher
  namespace: default
spec:
  jobTargetRef:
    parallelism: 1
    completions: 1
    backoffLimit: 4
    template:
      spec:
        affinity:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                - key: agentpool
                  operator: In
                  values:
                  - system
        serviceAccount: sa-keda-sb-kubectl
        containers:
        - name: servicebus-dispatcher
          image: stormbreakeracrdc.azurecr.io/misc/servicebus-dispatcher:1.0
          imagePullPolicy: Always
          command: ["python3", "/usr/src/app/servicebus_dispatcher.py"]          
          env:
          - name: SERVICE_BUS_FQDN
            value: 'dc-sb-test.servicebus.windows.net'
          - name: SERVICE_BUS_QUEUE_DISPATCH
            value: "dispatch"
          - name: SERVICE_BUS_QUEUE_RUNNING
            value: "running"
          volumeMounts:
          - name: input
            mountPath: "/mnt/input"
            readOnly: false
          - name: output
            mountPath: "/mnt/output"
            readOnly: false
        restartPolicy: Never
        volumes:
        - name: input
          persistentVolumeClaim:
            claimName: pvc-input
        - name: output
          persistentVolumeClaim:
              claimName: pvc-output
  pollingInterval: 10
  maxReplicaCount: 1
  successfulJobsHistoryLimit: 5
  failedJobsHistoryLimit: 2
  triggers:
  - type: azure-servicebus  
    metadata:  
      queueName: dispatch  # service bus queue
      queueLength: '1'
      namespace: SERVICEBUS_NAME  # service bus namespace
    authenticationRef:
      name: azure-servicebus-auth
---
# delete
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: servicebus-remover
  namespace: default
spec:
  jobTargetRef:
    parallelism: 1
    completions: 1
    backoffLimit: 4
    template:
      spec:
        affinity:
            nodeAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                nodeSelectorTerms:
                - matchExpressions:
                  - key: agentpool
                    operator: In
                    values:
                    - system
        serviceAccount: sa-keda-sb-kubectl
        containers:
        - name: servicebus-remover
          image: stormbreakeracrdc.azurecr.io/misc/servicebus-remover:1.0
          imagePullPolicy: Always
          command: ["python3", "/usr/src/app/servicebus_remover.py"]          
          env:
          - name: SERVICE_BUS_FQDN
            value: 'dc-sb-test.servicebus.windows.net'
          - name: SERVICE_BUS_QUEUE_DELETE
            value: "delete"
          - name: SERVICE_BUS_QUEUE_RUNNING
            value: "running"
          volumeMounts:
          - name: input
            mountPath: "/mnt/input"
            readOnly: false
          - name: output
            mountPath: "/mnt/output"
            readOnly: false
        restartPolicy: Never
        volumes:
        - name: input
          persistentVolumeClaim:
            claimName: pvc-input
        - name: output
          persistentVolumeClaim:
              claimName: pvc-output
  pollingInterval: 10
  maxReplicaCount: 1
  successfulJobsHistoryLimit: 5
  failedJobsHistoryLimit: 2
  triggers:
  - type: azure-servicebus  
    metadata:  
      queueName: delete # service bus queue
      queueLength: '1'
      namespace: SERVICEBUS_NAME # service bus namespace
    authenticationRef:
      name: azure-servicebus-auth
