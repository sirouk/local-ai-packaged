#!/usr/bin/env python3
"""
Fix .env file and deploy SOTA RAG with proper credentials
"""

import json
import os
import subprocess
import secrets


def generate_credential_id():
    return secrets.token_hex(8)


def fix_env_file():
    """Fix the .env file with proper API keys"""
    print("Fixing .env file...")

    # Read current .env
    env_lines = []
    api_keys = {}

    if os.path.exists(".env"):
        with open(".env", "r") as f:
            lines = f.readlines()

        # Fix the multi-line API key issue
        i = 0
        while i < len(lines):
            line = lines[i].strip()

            if line.startswith("OPENAI_API_KEY="):
                # Reconstruct the full API key
                api_key = line.split("=", 1)[1]
                # Check if next lines continue the key
                j = i + 1
                while j < len(lines) and not lines[j].strip().startswith(
                    ("MISTRAL_API_KEY", "COHERE_API_KEY", "#")
                ):
                    api_key += lines[j].strip()
                    j += 1
                api_keys["OPENAI_API_KEY"] = api_key
                i = j - 1
            elif line.startswith("MISTRAL_API_KEY="):
                api_keys["MISTRAL_API_KEY"] = line.split("=", 1)[1]
            elif line.startswith("COHERE_API_KEY="):
                api_keys["COHERE_API_KEY"] = line.split("=", 1)[1]
            elif line.startswith("ZEP_API_KEY="):
                api_keys["ZEP_API_KEY"] = line.split("=", 1)[1]
            elif not line.startswith(
                ("OPENAI_API_KEY", "MISTRAL_API_KEY", "COHERE_API_KEY")
            ):
                env_lines.append(lines[i])

            i += 1

        # Write back the corrected .env
        with open(".env", "w") as f:
            for line in env_lines:
                f.write(line)

            # Add corrected API keys
            f.write("\n# SOTA RAG API Keys (Corrected)\n")
            for key, value in api_keys.items():
                if value and value != "xxxxxx":
                    f.write(f"{key}={value}\n")

    return api_keys


def create_credentials_directly(api_keys):
    """Create n8n credentials directly with API keys"""
    print("Creating n8n credentials...")

    # Read other required values
    service_role_key = ""
    postgres_password = ""

    with open(".env", "r") as f:
        for line in f:
            if line.startswith("SERVICE_ROLE_KEY="):
                service_role_key = line.split("=", 1)[1].strip()
            elif line.startswith("POSTGRES_PASSWORD="):
                postgres_password = line.split("=", 1)[1].strip()

    # Generate credential IDs
    cred_ids = {
        "openai": generate_credential_id(),
        "mistral": generate_credential_id(),
        "supabase": generate_credential_id(),
        "postgres": generate_credential_id(),
        "cohere": generate_credential_id(),
    }

    credentials = []

    # OpenAI
    if api_keys.get("OPENAI_API_KEY"):
        credentials.append(
            {
                "id": cred_ids["openai"],
                "name": "OpenAI SOTA RAG",
                "type": "openAiApi",
                "data": {"apiKey": api_keys["OPENAI_API_KEY"]},
            }
        )
        print(f"  ✓ OpenAI credential: {cred_ids['openai']}")

    # Mistral
    if api_keys.get("MISTRAL_API_KEY"):
        credentials.append(
            {
                "id": cred_ids["mistral"],
                "name": "Mistral SOTA RAG",
                "type": "mistralCloudApi",
                "data": {"apiKey": api_keys["MISTRAL_API_KEY"]},
            }
        )
        print(f"  ✓ Mistral credential: {cred_ids['mistral']}")

    # Supabase
    if service_role_key:
        credentials.append(
            {
                "id": cred_ids["supabase"],
                "name": "Supabase SOTA RAG",
                "type": "supabaseApi",
                "data": {"host": "http://kong:8000", "serviceRole": service_role_key},
            }
        )
        print(f"  ✓ Supabase credential: {cred_ids['supabase']}")

    # Postgres
    if postgres_password:
        credentials.append(
            {
                "id": cred_ids["postgres"],
                "name": "Postgres SOTA RAG",
                "type": "postgres",
                "data": {
                    "host": "supabase-db",
                    "port": 5432,
                    "database": "postgres",
                    "user": "supabase_admin",
                    "password": postgres_password,
                },
            }
        )
        print(f"  ✓ Postgres credential: {cred_ids['postgres']}")

    # Cohere
    if api_keys.get("COHERE_API_KEY") and api_keys["COHERE_API_KEY"] != "xxxxxx":
        credentials.append(
            {
                "id": cred_ids["cohere"],
                "name": "Cohere SOTA RAG",
                "type": "httpHeaderAuth",
                "data": {
                    "name": "Authorization",
                    "value": f"Bearer {api_keys['COHERE_API_KEY']}",
                },
            }
        )
        print(f"  ✓ Cohere credential: {cred_ids['cohere']}")

    return credentials, cred_ids


def import_credentials(credentials):
    """Import credentials to n8n"""
    if not credentials:
        return False

    # Save credentials
    with open("/tmp/sota_creds.json", "w") as f:
        json.dump(credentials, f, indent=2)

    # Import to n8n
    result = subprocess.run(
        ["docker", "cp", "/tmp/sota_creds.json", "n8n:/tmp/creds.json"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"❌ Copy failed: {result.stderr}")
        return False

    result = subprocess.run(
        [
            "docker",
            "exec",
            "n8n",
            "n8n",
            "import:credentials",
            "--input=/tmp/creds.json",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"❌ Import failed: {result.stderr}")
        return False

    print(f"✅ Imported {len(credentials)} credentials")
    return True


def update_and_import_workflow(workflow_file, cred_ids):
    """Update workflow with credentials and import"""
    print(f"Processing: {workflow_file}")

    with open(workflow_file, "r") as f:
        workflow = json.load(f)

    # Map old IDs to new ones
    id_map = {
        "MM0xMOJkVoJoWOLP": cred_ids["openai"],
        "rmhBwssORDiWOBKN": cred_ids["mistral"],
        "wwbxqbDc4H2RPQ1Y": cred_ids["supabase"],
        "7aOzWLaZcz9dgeSv": cred_ids["postgres"],
        "SaJzpmSGdmOFSPDn": cred_ids.get("cohere", cred_ids["openai"]),  # fallback
    }

    updates = 0
    for node in workflow.get("nodes", []):
        if "credentials" in node:
            for cred_type, cred_info in node["credentials"].items():
                old_id = cred_info.get("id", "")
                if old_id in id_map:
                    cred_info["id"] = id_map[old_id]
                    updates += 1

    # Save updated workflow
    temp_file = f"/tmp/sota_workflow_{os.path.basename(workflow_file)}"
    with open(temp_file, "w") as f:
        json.dump(workflow, f, indent=2)

    # Import to n8n
    result = subprocess.run(
        ["docker", "cp", temp_file, "n8n:/tmp/import.json"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        result = subprocess.run(
            [
                "docker",
                "exec",
                "n8n",
                "n8n",
                "import:workflow",
                "--input=/tmp/import.json",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            print(f"  ✅ Imported with {updates} credential updates")
            return True

    print(f"  ❌ Import failed")
    return False


def main():
    print("SOTA RAG Fix and Deploy")
    print("=" * 30)

    # Fix .env file
    api_keys = fix_env_file()
    print(f"Found API keys: {list(api_keys.keys())}")

    # Create and import credentials
    credentials, cred_ids = create_credentials_directly(api_keys)
    if not import_credentials(credentials):
        return 1

    # Import workflows (Knowledge Graph first as it's a dependency)
    workflows = [
        "workflows/sota/knowledge-graph.json",  # Required dependency
        "workflows/sota/main-sota-rag.json",  # Main workflow (v2.1)
    ]

    imported = 0
    for workflow in workflows:
        if os.path.exists(workflow):
            if update_and_import_workflow(workflow, cred_ids):
                imported += 1

    print(f"\n✅ SOTA RAG deployment complete!")
    print(f"   Credentials: {len(credentials)} imported")
    print(f"   Workflows: {imported} imported")
    print(f"\n🎉 Ready to use at http://localhost:5678")

    return 0


if __name__ == "__main__":
    exit(main())
