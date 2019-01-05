#! /bin/bash

# Author:       Keith Patton
# Created:      2019-01
# Brief:        A BASH script to generate:
#               * password-protected Root Certificate Authority; key, CSR and self-signed certificate
#               * (per-project) Intermediate Certificate Authority; key, CSR and certificate (signed by Root CA)
#               * (multiple) Server SSL Certificate; key, CSR and certificate (signed by per-project Intermediate CA)
 
# Defaults:     certificate directory   {DIR}/certs/
#               private keys directory  {DIR}/private/
#               serial number record    {DIR}/serial
#               issued certs record     {DIR}/index.txt
#               Certificate Revocation List     {DIR}/crl/crl.pem
#               key bitsize: 4096 (Root), 2048 (Int), 1024 (Server)
#               key expiry: 30 years (Root) 10 years (Int) 5 years (Server)


## SET THE SCRIPT TO CREATE EITHER ROOT OR INTERMEDIATE CERTS
while true; do

  read -p "Create Root, Intermediate or Server certs? (Type 'root','int' or 'server'): " CERT_INPUT

  ## DEFINE THE VARIABLES FOR THIS SCRIPT DEPENDING UPON INPUT PREVIOUSLY SUPPLIED BY THE USER
  case "$CERT_INPUT" in
    root )
      DIR='../ca/root'; # Certificate Authority path relative to this script
      CNF="$DIR/openssl_${CERT_INPUT}.cnf"
      CSR="$DIR/csr/${CERT_INPUT}.ca.req.pem"; # Define the relative path and filename of the Certificate Siging Request
      CRT="$DIR/certs/${CERT_INPUT}.ca.crt.pem"; # Define the relative path and filename of the Certificate
      KEY="$DIR/private/${CERT_INPUT}.ca.key.pem"; # Define the relative path and filename of the Private Key
      DEF_KEY_SIZE="4096";
      break;;
    int )
      DIR='../ca/intermediate';
      CNF="$DIR/openssl_${CERT_INPUT}.cnf"
      KEY_ROOT="../ca/root/private/root.ca.key.pem"; # Define the relative path and filename of the Root CA Private Key (used for signing Intermediate CSR)
      DEF_KEY_SIZE="2048";
      break;;
    server )
      DEF_KEY_SIZE="512";
      break;;
    * )
      echo 'Please input either root, int or server';
  esac

done


## OBTAIN THE CURRENT PROJECT NAME IF CREATING INTERMEDIATE CERTIFICATES
function chooseProject() {
  while true; do
    clear

    read -p \
"Please choose a project name from the list below.
1) PROJECT 1
2) PROJECT 2
....etc.

Enter a number: " PROJECT_INPUT  

    case "$PROJECT_INPUT" in
      1 )
        PROJECT='project_1';
        PROJECT_UPPER='PROJECT_1';
        break;;
      2 )
        PROJECT='project_2';
        PROJECT_UPPER='PROJECT_2';
        break;;
      * ) ;;
    esac
  done
}


if [[ "$CERT_INPUT" == 'int' ]]; then

  chooseProject;

  CSR="$DIR/csr/${CERT_INPUT}.${PROJECT}.req.pem";
  CRT="$DIR/certs/${CERT_INPUT}.${PROJECT}.crt.pem";
  KEY="$DIR/private/${CERT_INPUT}.${PROJECT}.key.pem";

elif [[ "$CERT_INPUT" == 'server' ]]; then

  chooseProject;

  read -p "Please enter the server FQDN (Example: something.tld.com): " SERVER

  DIR="../server_certs"; # Servers working directory path relative to this script
  PROJECT_DIR="$DIR/$PROJECT";
  CNF="$DIR/openssl_server.cnf";
  CSR="$PROJECT_DIR/csr/${SERVER}.req.pem";
  CRT="$PROJECT_DIR/certs/${SERVER}.crt.pem";
  KEY="$PROJECT_DIR/private/${SERVER}.key.pem";
  KEY_INT="../ca/intermediate/private/int.${PROJECT}.key.pem"; # Define the relative path and filename of the INTER CA Private Key
  CRT_INT="../ca/intermediate/certs/int.${PROJECT}.crt.pem"; # Define the relative path and filename of the INTER CA CRT

fi


## CONFIRM CORRECT OPERATION OF SCRIPT
# Check working directory exists and is below the current script
if [ ! -d "$DIR" ]; then

  # Print error if 'ca/root' or 'ca/intermediate' directory is not available
  printf "Looks like you aren't executing this script from the correct directory, or directory "$DIR" does not exist!\n"
  printf "This script should be executed from within openssl_pki_tool/scripts/\n\n"
  printf "Directory structure MUST reflect the following layout...\n\n"
  
  # Print the correct directory structure
cat <<EOF
openssl_pki_tool/
├── ca
│   ├── intermediate
│   │   ├── certs
│   │   ├── clr
│   │   ├── csr
│   │   ├── index.txt
│   │   ├── openssl_int.cnf
│   │   └── private
│   └── root
│       ├── certs
│       ├── crl
│       ├── csr
│       ├── index.txt
│       ├── openssl_root.cnf
│       └── private
├── README.md
├── scripts
│   ├── new_ca_certs.sh ## THIS SCRIPT
├── server_certs
│   ├── {PROJECT} # PROJECT SPECIFIC WORKING DIRECTORY
│   │   ├── certs
│   │   ├── csr
│   │   ├── index.txt
│   │   └── private
│   ├── openssl_server.cnf # SERVER SPECIFIC CONFIG FILE
│   └── README.md
EOF

  # Print the current working directory
  printf "\nYour current working directory is:"
  pwd

  # Exit the script
  exit 1
 
fi


## MODIFY OPENSSL CONFIG FILES WITH VARIABLES FROM USER INPUT
case "$CERT_INPUT" in
  int ) 
    # Set the SSL commonName to that of the project (revert at end of script)
    sed -i "s#_change_me_commonName_#$PROJECT_UPPER Inter CA#g" $CNF;;
  server )
    # Modify the openssl_server.cnf file with variable values from user input (revert at end of script)
    sed -i "s#_change_me_dir_#$PROJECT_DIR#g" $CNF;
    sed -i "s#_change_me_crt_#$CRT_INT#g" $CNF;
    sed -i "s#_change_me_key_#$KEY_INT#g" $CNF;
    sed -i "s#_change_me_fqdn_#$SERVER#g" $CNF;
esac


## FOR SERVER CERTS, CHECK THE PROJECT DIRECTORY EXISTS AND CREATE IF NON-EXISTENT
if [[ "$CERT_INPUT" == 'server' ]] && [[ ! -d "$PROJECT_DIR" ]]; then
  mkdir -p "$PROJECT_DIR/"{certs,csr,private};
  touch "$PROJECT_DIR/index.txt"
  touch "$PROJECT_DIR/index.txt.attr"
fi


# CAPTURE INPUT FOR THE KEY SIZE IN BITS
read -p "Enter key size in bits (default $DEF_KEY_SIZE): " -i $DEF_KEY_SIZE -e KEY_SIZE


## BACKUP ANY EXISTING CERTIFICATES
# Check if any previous CSR exist and create a backup
if [ -f "$CSR" ]; then
  mv "$CSR" "${CSR}_$(date '+%F_%T').pem"
fi

# Check if any previous CRT exist and create a backup
if [ -f "$CRT" ]; then
  mv "$CRT" "${CRT}_$(date '+%F_%T').pem"
fi

# Check if any previous KEY exist and create a backup
if [ -f "$KEY" ]; then
  mv "$KEY" "${KEY}_$(date '+%F_%T').pem"
fi


## GENERATE A NEW PRIVATE KEY, CSR AND CA CERTIFICATE
# Generate a new RSA private key and Certificate Signing Request
case "$CERT_INPUT" in
  root )
    # Generate CSR and KEY - require a password
    openssl req -new -newkey rsa:$KEY_SIZE -keyout $KEY -out $CSR -config $CNF;;
  int )
    # Generate CSR and KEY - do not require a password
    openssl req -nodes -new -newkey rsa:$KEY_SIZE -keyout $KEY -out $CSR -config $CNF;;
  server )
    # Generate CSR and KEY - do not require a password
    openssl req -nodes -new -newkey rsa:$KEY_SIZE -keyout $KEY -out $CSR -config $CNF;;
esac

# Confirm the Key was generated and placed in the correct folder before proceeding
if [ ! -f "$KEY" ]; then
  echo "Error : something went wrong, $KEY does not exist!"
  exit 1
# Confirm the CSR was generated and placed in the correct folder before proceeding
elif [ ! -f "$CSR" ]; then
  echo "Error : something went wrong, $CSR does not exist!"
  exit 1
else
  # Confirm success and notify of proceeding to generate self-signed CA
  echo "Key and CSR generated successfully. Continuing..."
  read -p "Press Enter to continue..."
  printf "\n"
fi  

# Generate a new Certificate Authority
case "$CERT_INPUT" in
  root )
    # Create the self-signed root CA
    openssl ca -create_serial -out $CRT -keyfile $KEY -selfsign -extensions v3_ca_has_san -config $CNF -infiles $CSR;;
  int )
    # Create the Intermediate CA signed by Root
    openssl ca -create_serial -out $CRT -keyfile $KEY_ROOT -extensions v3_ca_has_san -config $CNF -infiles $CSR;
   # Revert the SSL commonName in the config file for future script sanity
   sed -i "s#$PROJECT_UPPER Inter CA#_change_me_commonName_#g" $CNF;;
  server )
    # Create the Server certificate
    openssl ca -create_serial -config $CNF -out $CRT -keyfile $KEY_INT -in $CSR
    # Revert the SSL commonName in the config file for future script sanity
    sed -i "s#$PROJECT_DIR#_change_me_dir_#g" $CNF;
    sed -i "s#$CRT_INT#_change_me_crt_#g" $CNF;
    sed -i "s#$KEY_INT#_change_me_key_#g" $CNF;
    sed -i "s#$SERVER#_change_me_fqdn_#g" $CNF;
esac
