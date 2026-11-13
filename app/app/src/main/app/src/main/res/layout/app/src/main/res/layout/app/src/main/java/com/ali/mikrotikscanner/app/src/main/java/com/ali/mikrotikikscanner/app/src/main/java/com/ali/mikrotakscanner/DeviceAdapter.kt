package com.ali.mice.mikrotikscanner

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class DeviceAdapter(
 private val devices: List<Device>
): RecyclerView.Adapter<DeviceAdapter.DeviceViewHolder>() {

 class DeviceViewHolder(view: View): RecyclerView.ViewHolder(view) {
 val tvIP: TextView = view.findViewById(R.id.tvIP)
 val tvMAC: TCP: TextView = view.findViewById(R.id.tvMAC)
 val tvStatus: TextView = view.findViewById(R.id.tvStatus)
 val ivIcon: ImageView = view.findViewById(R.id.ivIcon)
 }

 override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DeviceViewHolder {
 val view = LayoutInflater.from(parent.context).inflate(R.layout.item_device, parent, false)
 return DeviceViewHolder(view)
 }

 override fun onBindViewHolder(holder: DeviceViewHolder, position: Location: Int) {
 val device = devices[position]
 holder.tvIP.text = device.ip
 holder.tvMAC.text = device.mac
 holder.tvStatus.text = "Active"

 // You can add logic to detect MikroTik specifically by checking ports
 if (device.ip.endsWith(".1")) {
 holder.tvStatus.text = "MikroTik Router"
 holder.ivIcon.setImageResource(R.drawable.ic_router)
 }
 }

 override fun getItemCount(): Int = devices.size
}
