package com.ali.mikrotikscanner

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View

import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

class MainActivity: AppCompatActivity() {

 private lateinit var recyclerView: RecyclerView
 private lateinit var btnScan: Button
 private lateinit var tvStatus: TextView
 private lateinit var deviceAdapter: DeviceAdapter
 private val deviceList = ArrayList<Device>()

 private val PERMISSION_REQUEST_CODE = 1001

 override fun onCreate(savedInstanceState: Bundle?) {
 super.onCreate(savedInstanceState)
 setContentView(R.layout.activity_main)

 initViews()
 checkPermissions()
 }

 private fun initViews() {
 recyclerView = findViewById(R.id.recyclerView)
 btnScan = findViewById(R.id.btnScan)
 tvStatus = findViewById(R.id.tvStatus)

 recyclerView.layoutManager = LinearLayoutManager(this)
 deviceAdapter = DeviceAdapter(deviceList)
 recyclerView.adapter = deviceAdapter

 btnScan.setOnClickListener {
 if (checkPermissions()) {
 performScan()
 } else {
 checkPermissions() // Request permissions if not granted
 }
 }
 }

 private fun checkPermissions() {
 val permissions = arrayOf(
 Manifest.permission.ACCESS_FINE_LOCATION,
 Manifest.permission.ACCESS_COARSE_LOCATION,
 Manifest.permission.ACCESS_WIFI_STATE,
 Manifest.permission.CHANGE_WIFI_STATE,
 Manifest.permission.INTERNET
 )

 var allGranted = true
 for (permission in permissions) {
 if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
 allGranted = false
 break
 }
 }

 if (!allGranted) {
 ActivityCompat.requestPermissions(this, permissions, PERMISSION_REQUEST_CODE)
 }
 }

 override fun onRequestPermissionsResult(
 requestCode: Int,
 permissions: Array<out String>,
 grantResults: IntArray
 ) {
 super.onRequestPermissionsResult(requestCode, permissions, grantResults)
 if (requestCode == PERMISSION_REQUEST_CODE) {
 var allGranted = true
 for (result in grantResults) {
 if (result != PackageManager.PERMISSION_GRANTED) {
 allGranted = false
 break
 }
 }
 if (!allGranted) {
 Toast.makeText(this, "Permissions are required to scan.", Toast.LENGTH_SHORT).show()
 } else {
 performScan()
 }
 }
 }

 private fun performScan() {
 tvStatus.text = "Scanning Network..."
 btnScan.isEnabled = false
 btnScan.alpha = 0.5f

 // Use a background thread to prevent UI lag
 Thread {
 val results = scanForMikroTik()

 Handler(Looper.getMainLooper()).post {
 deviceList.clear()
 deviceList.addAll(results)
 deviceAdapter.notifyDataSetChanged()
 tvStatus.text = "Scan Complete. Found ${results.size} devices."
 btnScan.isEnabled = true
 btnScan.alpha = 1f
 }
 }.start()
 }

 private fun scanForMikroTik(): List<Device> {
 // 1. Get local IP and Subnet Mask
 val localIp = getLocalIpAddress()
 val mask = getSubnetMask()

 if (localIp == null || mask == null) {
 return emptyList()
 }

 val ipPrefix = localIp.substring(0, localIp.lastIndexOf(".")) + "."
 val ipSuffix = localIp.substring(localIp.lastIndexOf(".") + 1)

 val discoveredIPs = mutableSetOf<String>()
 
 // 2. Scan IPs in range (e.g., 192.168.88.1 to 192.168.88.254)
 // You can adjust this range or make it dynamic
 for (i in 1..254) {
 val checkIP = "$ipPrefix$i"
 
 // Check if IP is different from local IP
 if (checkIP != localIp) {
 // Simulate ARP Scan (In a real app, you would use Nmap or a raw socket ARP request)
 // For this demo, we simulate scanning by checking port 80 (HTTP) or 8291 (MikroTik API)
 if (isPortOpen(checkIP, 80) || isPortOpen(checkIP, 8291)) {
 discoveredIPs.add(checkIP)
 }
 }
 
 // Update status every 10 IPs to show progress
 if (i % 10 == 0) {
 Handler(Looper.getMainLooper()).post {
 tvStatus.text = "Scanning: $checkIP..."
 }
 }
 }

 // 3. Simulate MAC Address and Vendor discovery
 return discoveredIPs.map { ip ->
 // In a real scenario, you would perform an ARP request to get the MAC
 val mac = "AA:BB:CC:DD:EE:FF" // Placeholder
 val vendor = "Unknown"
 Device(ip, mac, vendor)
 }
 }

 // Helper to get Local IP
 private fun getLocalIpAddress(): String? {
 val runtime = Runtime.getRuntime()
 try {
 val exec = runtime.exec("/system/bin/cat /proc/net/route")
 val reader = BufferedReader(InputStreamReader(exec.inputStream))
 var line: String?
 while (reader.readLine().also { line = it } != null) {
 if (line!!.contains("00000000")) {
 val destination = line!!.split("\\s+".toRegex()).toTypedArray()
 return destination[1]
 }
 }
 } catch (e: Exception) {
 e.printStackTrace()
 }
 return null
 }

 // Helper to get Subnet Mask
 private fun getSubnetMask(): String? {
 val runtime = Runtime.getRuntime()
 try {
 val exec = runtime.exec("/system/bin/cat /proc/net/route")
 val reader = BufferedReader(InputStreamReader(exec.inputStream))
 var line: String?
 while (reader.readLine().also { line = it } != null) {
 if (line!!.contains("00000000")) {
 val destination = line!!.split("\\s+".toRegex()).toTypedArray()
 return destination[7]
 }
 }
 } catch (e: Exception) {
 e.printStackTrace()
 }
 return null
 }

 // Helper to check if a port is open
 private fun isPortOpen(ip: String, port: Int): Boolean {
 try {
 val socket = Socket(ip, port)
 socket.close()
 return true
 } catch (e: Exception) {
 return false
 }
 }
}
