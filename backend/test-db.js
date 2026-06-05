const mysql = require("mysql2");

const connection = mysql.createConnection({
  host: "kodama.proxy.rlwy.net",
  port: 23544,
  user: "root",
  password: "AOWaRcGXzUUccrhnNlBTOEgqGUsPeJAr",
  database: "railway"
});

connection.connect((err) => {
  if (err) {
    console.log("❌ DB connection failed:");
    console.log(err.message);
  } else {
    console.log("✅ DB connected successfully!");
  }

  connection.end();
});