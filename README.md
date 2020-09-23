# webhook-pro
目前 Kubernetes 中已经有非常多的 Admission 插件， 但是并不能保证满足所有开发者的需求。 众所周知，Kbernetes 之所以受到推崇，
它的可扩展能力功不可没。Admission 也提供了一种 webhook 的扩展机制。

```text
1. MutatingAdmissionWebhook：在对象持久化之前进行修改
2. ValidatingAdmissionWebhook：在对象持久化之前进行验证
```
准入控制分两个阶段进行，第一阶段，运行 mutating admission 控制器，第二阶段运行 validating admission 控制器。我们的本次实验需求主要是实现ValidatingAdmissionWebhook 的功能测试。

#### 开发测试环境

```text
golang version： go1.13.12
k8s version: 1.18.3
```

#### kube-apiserver 配置
确保在 apiserver 中启用了MutatingAdmissionWebhook 和 ValidatingAdmissionWebhook这两个控制器：

```
- --enable-admission-plugins=...,MutatingAdmissionWebhook,ValidatingAdmissionWebhook
```
然后通过运行下面的命令检查集群中是否启用了准入注册 API：
```
# kubectl api-versions |grep admission
admissionregistration.k8s.io/v1beta1
```

####  webhook server开发
代码中主要的逻辑在两个文件中：main.go和webhook.go，main.go文件包含创建 HTTP 服务的代码，而webhook.go包含 validates  webhook 的逻辑，大部分代码都比较简单，首先查看main.go文件，查看如何使用标准 golang 包来启动 HTTP 服务，以及如何从命令行标志中读取 TLS 配置的证书：

1. 实现webhook http server逻辑, 关键业务代码,注册/validate 路由

```golang
// define http server and server handler
mux := http.NewServeMux()
mux.HandleFunc("/validate", whsvr.serve)
whsvr.server.Handler = mux

// start webhook server in new routine
go func() {
    if err := whsvr.server.ListenAndServeTLS("", ""); err != nil {
        glog.Errorf("Failed to listen and serve webhook server: %v", err)
    }
}()
```

1. 实现webhook 注入逻辑, 关键业务代码, 判断是否删除的是dmz 命名空间中的pods :

```golang
// validate delete pods
func (whsvr *WebhookServer) validate(ar *v1beta1.AdmissionReview) *v1beta1.AdmissionResponse {
	req := ar.Request
	var (
		resourceName string
		allowed      = true
		result       *metav1.Status
	)

	if req.Namespace == "dmz" {
		allowed = false
		result = &metav1.Status{
			Reason: "protect ns, delete pod forbbiden...",
		}
	}
	return &v1beta1.AdmissionResponse{
		Allowed: allowed,
		Result:  result,
	}
}
```

#### 编译
```
# export DOCKER_USER=ccr.ccs.tencentyun.com/webhook
# ./build
```
编译成功之后，会将容器镜像直接push到镜像仓库，这里的DOCKER_USER根据个人的环境可以进行修改，如果push失败，会在本地存储:
```
[root@VM_10_60_centos ~/code/gopath/src/webhook-pro]# docker images
REPOSITORY                                                            TAG                            IMAGE ID            CREATED             SIZE
ccr.ccs.tencentyun.com/webhook/webhook-pro                            v1                             3ee45c8c502a        About an hour ago   27.2MB
```

#### 部署

1. 生成证书信息，存放到secret中 admission-webhook-example-certs，当 webhook server启动的时候，会挂载该secrete到指定位置；
```
# ./deployment/webhook-create-signed-cert.sh
creating certs in tmpdir /tmp/tmp.ug7z6ui1b9 
Generating RSA private key, 2048 bit long modulus
............................................................................................................+++
...................................................................................................................................+++
e is 65537 (0x10001)

certificatesigningrequest.certificates.k8s.io/admission-webhook-example-svc.default created
NAME                                    AGE   REQUESTOR   CONDITION
admission-webhook-example-svc.default   0s    admin       Pending
certificatesigningrequest.certificates.k8s.io/admission-webhook-example-svc.default approved
secret/admission-webhook-example-certs configured
```
2. 创建webhook server以及对应的service， kube-apiserver会通过servicename 来调用webhook server的接口的：
```bash
# kubectl create -f deployment/deployment.yaml
deployment.apps "admission-webhook-example-deployment" created

# kubectl create -f deployment/service.yaml
service "admission-webhook-example-svc" created
```
3. 配置webhook

CA 证书应提供给 admission webhook 配置，这样 apiserver 才可以信任 webhook server 提供的 TLS 证书。因为我们上面已经使用 Kubernetes API 签署了证书，所以我们可以使用我们的 kubeconfig 中的 CA 证书来简化操作。代码仓库中也提供了一个小脚本用来替换 CA_BUNDLE 这个占位符，创建 validating webhook 之前运行该命令即可：如下：
```
# cat ./deployment/validatingwebhook.yaml | ./deployment/webhook-patch-ca-bundle.sh > ./deployment/validatingwebhook-ca-bundle.yaml
# cat ./deployment/validatingwebhook-ca-bundle.yaml
apiVersion: admissionregistration.k8s.io/v1beta1
kind: ValidatingWebhookConfiguration
metadata:
  name: validation-webhook-example-cfg
  labels:
    app: admission-webhook-example
webhooks:
  - name: required-labels.banzaicloud.com
    clientConfig:
      service:
        name: admission-webhook-example-svc
        namespace: default
        path: "/validate"
      caBundle: LS0tLS1CRUdJDZiV0Z6ZEdWeQpjekVWTUJNR0ExVUVBeE1NWTJ4ekxXbzRObUo1YnpkNk1CNFhEVEl3TURreU1qRTBORFV4TVZvWERUUXdNRGt5Ck1qRTBORFV4TVZvd1VERUxNQWtHQTFVRUJoTUNRMDR4S2pBUkJnTlZCQW9UQ25SbGJtTmxiblI1ZFc0d0ZRWUQKVlFRS0V3NXplWE4wWlcwNmJXRnpkR1Z5Y3pFVk1CTUdBMVVFQXhNTVkyeHpMV280Tm1KNWJ6ZDZNSUlCSWpBTgpCZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUFxcnJjeitoNlB4MHVRRTEydDR5YVNUYjAyTzUyCmMzbW1GbU9yaHB5bEFsbjN6cjNaMU42b3pqSVRuakxBVWgyOTAwdUlhQkFsNXo1d2ZQUlhsbmNZNDlDbitoRDgKd0lyeG1XVmk5Ry9ocHpuYjQwa2ExTThFNEk5ZkFoOCtPZENraUMrOVB3MTZNUDU1WGpQeUlLS0FhVErbWsKOGFqQ1JObWpFL2VVeE44V1hkRnd5cWNYcU1uSXRPd1U4R2tVSUJpSTFvLzRyZjZBSWlEL0dVa0lHUUlEQVFBQgpvMEl3UURBT0JnTlZIUThCQWY4RUJBTUNBb1F3SFFZRFZSMGxCQll3RkFZSUt3WUJCUVVIQXdJR0NDc0dBUVVGCkJ3TUJNQThHQTFVZEV3RUIvd1FGTUFNQkFmOHdEUVlKS29aSWh2Y05BUUVMQlFBRGdnRUJBRVhtTXF3RkdzRFoKWjJqbUdYaUpMSUtRYXd6WDFYaEJYWk45NWJXOHVzU0xJR3Exck5FaGRIQnMrRmRqelNDSFM3SitXU0txN3hQeQpEN1VCQ0lNL3pPZmFjSUdRWTJGTkp3Y3F1QXFOR0ZQa1BKYjJSU3d0NG1aSnFhT3phRi9vaW91bXE2M1hQMDM4CmZvdzRqMWt1ODlQa2ljYlNYNDAyc2c0UXV5MEJGcjhUVW9JdENKOENDeFV4TVpIU3VsSnlvUG81d1FESlNIcnMKUXMrcjVZeXBwTzhyNU9Wb3dYb2xVbm9tR24raXpxVSt2Y2Vtck1aQkVzVzJCT2JJdVViTHRoWW55YlBqZVBwTgpnOHJadm1kL2RoNGVNNlZaKzgrZHBlQTkxMCtuWVNrZnlBdzFTc2grVy9mNUc4NnZ1QnA3aWhpWkpqMUlKUWZvCjVjaDE5ZDZoYzFBPQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    ......
```
4. 通过 namespaceSelector 来匹配目标namespace, 只有设置了该lable的 namespace, 其操作才会发送到webhook server进行验证，比如:
```yaml
namespaceSelector:
  matchLabels:
    admission-webhook-example: enabled
``` 


#### 验证测试
1. 创建dmz namespace，并给dmz 命名空间设置 webhook验证的lable:

```bash
root@10-0-7-5 deployment]#  kubectl create ns dmz
root@10-0-7-5 deployment]#  kubectl label namespace dmz admission-webhook-example=enabled
```

2. 在dmz 空间创建 一个deployment: 
```bash
[root@10-0-7-5 deployment]# kubectl  create -f deployment/sleep-dmz.yaml 
deployment.apps/sleep created
[root@10-0-7-5 deployment]# kubectl  get pod -n dmz
NAME                    READY   STATUS    RESTARTS   AGE
sleep-bb596f69d-f4f5m   1/1     Running   0          7s
sleep-bb596f69d-fvj2v   1/1     Running   0          7s
sleep-bb596f69d-k8jlz   1/1     Running   0          7s
```
3. 测试删除 dmz 命名空间中的pod：

```bash
[root@10-0-7-5 deployment]# kubectl delete pod sleep-bb596f69d-f4f5m -n dmz
Error from server (protect ns, delete forbbiden...): admission webhook "required-labels.banzaicloud.com" denied the request: protect ns, delete forbbiden...
```

#### 总结
webhook 作为

#### 参考

https://github.com/kubernetes/kubernetes/blob/v1.10.0-beta.1/test/images/webhook/main.go

https://github.com/banzaicloud/admission-webhook-example
