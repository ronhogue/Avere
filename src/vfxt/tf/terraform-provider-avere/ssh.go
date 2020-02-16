// Copyright (C) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See LICENSE-CODE in the project root for license information.
package main

import (
	"bytes"
	"fmt"
	"io"
	"io/ioutil"
	"os/user"
	"sync"
	
	"golang.org/x/crypto/ssh"
)

func GetPasswordAuthMethod(password string) (ssh.AuthMethod) {
	return ssh.Password(password)
}

func GetKeyFileAuthMethod() (authMethod ssh.AuthMethod, err error) {
    usr, _ := user.Current()
	file := usr.HomeDir + "/.ssh/id_rsa"
	buf, err := ioutil.ReadFile(file)
    if err != nil {
		return
    }
    key, err := ssh.ParsePrivateKey(buf)
    if err != nil {
        return
	}
	authMethod = ssh.PublicKeys(key)
    return
}

// SSHCommand runs an ssh command, and captures the stdout and stderr in two byte buffers
func SSHCommand(host string, username string, authMethod ssh.AuthMethod, cmd string) (bytes.Buffer, bytes.Buffer, error) {
	var stdoutBuf, stderrBuf bytes.Buffer

	sshConfig := &ssh.ClientConfig {
		User: username,
		Auth: []ssh.AuthMethod {
			authMethod,
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
	}
	connection, err := ssh.Dial("tcp", fmt.Sprintf("%s:22", host), sshConfig)
	if err != nil {
		return stdoutBuf, stderrBuf, fmt.Errorf("failed to create connection: %s", err)
	}
	session, err := connection.NewSession()
	if err != nil {
		return stdoutBuf, stderrBuf, fmt.Errorf("failed to get new session: %s", err)
	}
	defer session.Close()

	stdoutIn, err := session.StdoutPipe()
	if err != nil {
		return stdoutBuf, stderrBuf, fmt.Errorf("Unable to setup stdout for session: %s", err)
	}

	stderrIn, err := session.StderrPipe()
	if err != nil {
		return stdoutBuf, stderrBuf, fmt.Errorf("Unable to setup stderr for session: %s", err)
	}

	if err := session.Start(cmd) ; err != nil {
		return stdoutBuf, stderrBuf, fmt.Errorf("failed to start the command: %s", err)
	}

	var wg sync.WaitGroup
	wg.Add(1)

	var errStdout, errStderr error
	go func() {
		_, errStdout = io.Copy(&stdoutBuf, stdoutIn)
		wg.Done()
	}()

	_, errStderr = io.Copy(&stderrBuf, stderrIn)
	wg.Wait()

	if err := session.Wait() ; err != nil {
		return stdoutBuf, stderrBuf, fmt.Errorf("cmd.Run failed with %s", err)
	}

	if errStdout != nil {
		return stdoutBuf, stderrBuf, fmt.Errorf("failed to capture stdout: %s", errStdout)
	}

	if errStderr != nil {
		return stdoutBuf, stderrBuf, fmt.Errorf("failed to capture stderr: %s", errStderr)
	}
	
	return stdoutBuf, stderrBuf, nil
}