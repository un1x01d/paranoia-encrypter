#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No color

# Function to generate RSA keys if they do not exist
generate_rsa_keys() {
    if [[ ! -f private_key.pem || ! -f public_key.pem ]]; then
        echo -e "${YELLOW}Generating RSA keys...${NC}"
        # Suppress output by redirecting to /dev/null
        openssl genpkey -algorithm RSA -out private_key.pem -pkeyopt rsa_keygen_bits:4096 >/dev/null 2>&1
        openssl rsa -pubout -in private_key.pem -out public_key.pem >/dev/null 2>&1
    else
        echo -e "${YELLOW}RSA keys already exist.${NC}"
    fi
}

# Function to encrypt a symmetric key using the RSA public key
encrypt_symmetric_key() {
    openssl pkeyutl -encrypt -inkey public_key.pem -pubin -in "$1" -out "$2"
}

# Function to decrypt a symmetric key using the RSA private key
decrypt_symmetric_key() {
    openssl pkeyutl -decrypt -inkey private_key.pem -in "$1" -out "$2"
}

# Function to AES encrypt a file
aes_encrypt() {
    openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"$1" -in "$2" -out "$3"
}

# Function to AES decrypt a file
aes_decrypt() {
    openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass pass:"$1" -in "$2" -out "$3"
}

# Function to ChaCha20 encrypt a file
chacha_encrypt() {
    openssl enc -chacha20 -pbkdf2 -salt -pass pass:"$1" -in "$2" -out "$3"
}

# Function to ChaCha20 decrypt a file
chacha_decrypt() {
    openssl enc -d -chacha20 -pbkdf2 -salt -pass pass:"$1" -in "$2" -out "$3"
}

# Main encryption function
encrypt() {
    local source_file="$1"
    local output_file="$2"

    # Check if the source file exists
    if [[ ! -f "$source_file" ]]; then
        echo -e "${RED}Error: Source file '$source_file' does not exist.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Encryption started at $(date)${NC}"
    SECONDS=0  # Start the timer

    generate_rsa_keys

    # Generate random passwords for AES and ChaCha20 encryption
    local aes_password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    local chacha_password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)

    # Temporary file paths
    local symmetric_key=$(mktemp /tmp/symmetric_key.XXXXXX)
    local encrypted_key=$(mktemp /tmp/encrypted_key.XXXXXX)
    local encrypted_data=$(mktemp /tmp/encrypted_data.XXXXXX)
    local chacha_encrypted_data=$(mktemp /tmp/chacha_encrypted_data.XXXXXX)

    # Step 1: Generate a symmetric key
    echo -e "${YELLOW}Generating symmetric key...${NC}"
    head -c 32 </dev/urandom >"$symmetric_key"

    # Step 2: Encrypt the symmetric key with RSA
    echo -e "${YELLOW}Encrypting symmetric key with RSA...${NC}"
    encrypt_symmetric_key "$symmetric_key" "$encrypted_key"

    # Step 3: Encrypt the data with AES using the password
    echo -e "${YELLOW}Encrypting data with AES...${NC}"
    aes_encrypt "$aes_password" "$source_file" "$encrypted_data"

    # Step 4: Encrypt the AES-encrypted data with ChaCha20 using the password
    echo -e "${YELLOW}Encrypting AES-encrypted data with ChaCha20...${NC}"
    chacha_encrypt "$chacha_password" "$encrypted_data" "$chacha_encrypted_data"
    rm -f "$encrypted_data"  # Remove the temporary AES-encrypted file

    # Step 5: Combine the encrypted key and ChaCha20-encrypted data into a single output file
    echo -e "${YELLOW}Combining encrypted key and ChaCha20-encrypted data...${NC}"
    cat "$encrypted_key" "$chacha_encrypted_data" >"$output_file"
    rm -f "$encrypted_key" "$chacha_encrypted_data" "$symmetric_key"  # Clean up temporary files

    # Display completion message and elapsed time
    local duration=$SECONDS
    echo -e "${GREEN}Encryption completed at $(date)${NC}"
    echo -e "${GREEN}Elapsed time: $(($duration / 60)) minutes and $(($duration % 60)) seconds${NC}"
    echo -e "${YELLOW}Output file: $output_file${NC}"
    echo -e "${YELLOW}AES Password: $aes_password${NC}"
    echo -e "${YELLOW}ChaCha20 Password: $chacha_password${NC}"
    echo -e "${YELLOW}Private Key Path: $(realpath private_key.pem)${NC}"
    echo -e "${YELLOW}Public Key Path: $(realpath public_key.pem)${NC}"
}

# Main decryption function
decrypt() {
    local source_file="$1"
    local output_file="$2"

    # Check if the encrypted file exists
    if [[ ! -f "$source_file" ]]; then
        echo -e "${RED}Error: Encrypted file '$source_file' does not exist.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Decryption started at $(date)${NC}"
    SECONDS=0  # Start the timer

    # Prompt for the AES and ChaCha20 passwords
    read -sp "Enter AES password: " aes_password
    echo
    read -sp "Enter ChaCha20 password: " chacha_password
    echo

    # Temporary file paths
    local encrypted_key=$(mktemp /tmp/encrypted_key.XXXXXX)
    local chacha_encrypted_data=$(mktemp /tmp/chacha_encrypted_data.XXXXXX)
    local symmetric_key=$(mktemp /tmp/symmetric_key.XXXXXX)
    local decrypted_data=$(mktemp /tmp/decrypted_data.XXXXXX)

    # Step 1: Split the input file into the encrypted key and ChaCha20-encrypted data
    echo -e "${YELLOW}Splitting input file into encrypted key and ChaCha20-encrypted data...${NC}"
    dd if="$source_file" of="$encrypted_key" bs=512 count=1 2>/dev/null  # Assuming a 4096-bit RSA key (512 bytes)
    dd if="$source_file" of="$chacha_encrypted_data" bs=512 skip=1 2>/dev/null

    # Step 2: Decrypt the symmetric key using the RSA private key
    echo -e "${YELLOW}Decrypting symmetric key with RSA...${NC}"
    if ! decrypt_symmetric_key "$encrypted_key" "$symmetric_key"; then
        echo -e "${RED}Error: Failed to decrypt the symmetric key.${NC}"
        rm -f "$encrypted_key" "$chacha_encrypted_data"
        exit 1
    fi

    # Step 3: Decrypt the ChaCha20-encrypted data using the password
    echo -e "${YELLOW}Decrypting ChaCha20-encrypted data...${NC}"
    if ! chacha_decrypt "$chacha_password" "$chacha_encrypted_data" "$decrypted_data"; then
        echo -e "${RED}Error: Failed to decrypt the ChaCha20-encrypted data. Please check the ChaCha20 password.${NC}"
        echo -e "${RED}Debug: Possible causes include an incorrect password or file corruption.${NC}"
        rm -f "$encrypted_key" "$chacha_encrypted_data" "$symmetric_key" "$decrypted_data"
        exit 1
    fi

    # Step 4: Decrypt the data using the AES password
    echo -e "${YELLOW}Decrypting data with AES...${NC}"
    if ! aes_decrypt "$aes_password" "$decrypted_data" "$output_file"; then
        echo -e "${RED}Error: Failed to decrypt the AES-encrypted data. Please check the AES password.${NC}"
        rm -f "$encrypted_key" "$chacha_encrypted_data" "$symmetric_key" "$decrypted_data"
        exit 1
    fi

    # Clean up temporary files
    rm -f "$encrypted_key" "$chacha_encrypted_data" "$symmetric_key" "$decrypted_data"

    # Display completion message and elapsed time
    local duration=$SECONDS
    echo -e "${GREEN}Decryption completed at $(date)${NC}"
    echo -e "${GREEN}Elapsed time: $(($duration / 60)) minutes and $(($duration % 60)) seconds${NC}"
    echo -e "${YELLOW}Output file: $output_file${NC}"
}

# Script entry point
main() {
    if [[ $# -lt 3 ]]; then
        echo -e "${RED}Usage:${NC}"
        echo "  $0 encrypt <source_file> <output_file>"
        echo "  $0 decrypt <source_file> <output_file>"
        exit 1
    fi

    local mode="$1"
    local source_file="$2"
    local output_file="$3"

    case "$mode" in
        encrypt)
            encrypt "$source_file" "$output_file"
            ;;
        decrypt)
            decrypt "$source_file" "$output_file"
            ;;
        *)
            echo -e "${RED}Unknown mode: $mode${NC}"
            echo -e "${RED}Usage:${NC}"
            echo "  $0 encrypt <source_file> <output_file>"
            echo "  $0 decrypt <source_file> <output_file>"
            exit 1
            ;;
    esac
}

main "$@"

