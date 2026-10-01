/**
 * The MIT License (MIT)
 * Copyright (c) 2026 Tim Fennell
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include <jni.h>

#include <initializer_list>
#include <stdlib.h>
#include <sys/stat.h>

namespace {

bool path_exists(const char* path) {
  struct stat info;
  return stat(path, &info) == 0;
}

/**
 * Points OpenSSL, and through it libcurl and the cloud SDKs, at the system's CA certificate bundle when there is no
 * /etc/ssl/cert.pem. A distributable library's OpenSSL looks for CA certificates only under /etc/ssl, where e.g.
 * RHEL 8 has neither that file nor certificates under OpenSSL's hashed names, so https connections to cloud storage
 * would fail. A location already chosen with SSL_CERT_FILE or SSL_CERT_DIR is left alone.
 */
void use_system_ca_certificates_if_needed() {
  if (getenv("SSL_CERT_FILE") || getenv("SSL_CERT_DIR") || path_exists("/etc/ssl/cert.pem")) {
    return;
  }
  //RHEL, Fedora and Amazon Linux; Debian, Ubuntu and Alpine; SUSE
  for (auto bundle : {"/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/certs/ca-certificates.crt", "/etc/ssl/ca-bundle.pem"}) {
    if (path_exists(bundle)) {
      setenv("SSL_CERT_FILE", bundle, 0);
      return;
    }
  }
}

}

/** Called by the JVM when it loads the library, before any of the library is used. */
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
  use_system_ca_certificates_if_needed();
  return JNI_VERSION_1_8;
}
