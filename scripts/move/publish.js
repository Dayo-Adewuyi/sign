require("dotenv").config();
const fs = require("node:fs");
const cli = require("@aptos-labs/ts-sdk/dist/common/cli/index.js");
const aptosSDK = require("@aptos-labs/ts-sdk");

async function publish() {
  const move = new cli.Move();

  move
    .createObjectAndPublishPackage({
      packageDirectoryPath: "contract",
      addressName: "noncesign_contract",
      namedAddresses: {
        noncesign_contract: process.env.NEXT_MODULE_PUBLISHER_ACCOUNT_ADDRESS,
      },
      extraArguments: [
        `--private-key=${process.env.NEXT_MODULE_PUBLISHER_ACCOUNT_PRIVATE_KEY}`,
        `--url=${aptosSDK.NetworkToNodeAPI[process.env.NEXT_PUBLIC_APP_NETWORK]}`,
      ],
    })
    .then((response) => {
      const filePath = ".env";
      let envContent = "";

      if (fs.existsSync(filePath)) {
        envContent = fs.readFileSync(filePath, "utf8");
      }

      const regex = /^NEXT_PUBLIC_MODULE_ADDRESS=.*$/m;
      const newEntry = `NEXT_PUBLIC_MODULE_ADDRESS=${response.objectAddress}`;

      if (envContent.match(regex)) {
        envContent = envContent.replace(regex, newEntry);
      } else {
        envContent += `\n${newEntry}`;
      }

      fs.writeFileSync(filePath, envContent, "utf8");
    });
}

publish();
