# webhook-pro
# webhook admission
目前 Kubernetes 中已经有非常多的 Admission 插件， 但是并不能保证满足所有开发者的需求。 众所周知，Kbernetes 之所以受到推崇，
它的可扩展能力功不可没。Admission 也提供了一种 webhook 的扩展机制。

```text
1. MutatingAdmissionWebhook：在对象持久化之前进行修改
2. ValidatingAdmissionWebhook：在对象持久化之前进行验证
```


#### 参考

https://github.com/kubernetes/kubernetes/blob/v1.10.0-beta.1/test/images/webhook/main.go
