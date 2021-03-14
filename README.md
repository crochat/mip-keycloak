# mip-keycloak

This is just to experiment MIP login through KeyCloak (local or remote instance).
The goal of it is mainly educational, to understand the authentication flow. That's why I did it with curl queries, without using external libraries.
In order to make it clearer, I also coded a small HTTP lib in bash.

Examples:
* ./mip_login.sh http://<MIP_HOSTNAME>
* ./mip_login.sh http://<MIP_HOSTNAME:<MIP_PORT>
* ./mip_login.sh http://<MIP_HOSTNAME>/services/sso/login
* ./mip_login.sh http://<MIP_HOSTNAME>/services/login/<EXTERNAL_IDENTITY_PROVIDER>

By default, if you don't specify anything after <MIP_HOSTNAME>, it will try with /services/sso/login (MIP < 6.4: local MIP only; MIP >= 6.4: local and federated MIP login).
Then, if it fails, it will try with the old way (pre MIP 6.4) of connecting to an external KeyCloak service, with /services/login/<EXTERNAL_IDENTITY_PROVIDER>.

As it stores cookies, after a successful login, you should be able to use it in another browser to get a working MIP connection.
By default, only a few informations about the flow will be printed out. If you want more defail, just add -v or -vv.
Starting from -v, you will get the HTML code of the last page on which it lands at the end of the process.
