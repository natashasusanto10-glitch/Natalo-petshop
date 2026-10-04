import React from "react";
export default function Image({fill,priority,placeholder,blurDataURL,quality,unoptimized,loader,sizes,style,...props}) {return <img {...props} style={{...(fill ? {position:"absolute",inset:0,width:"100%",height:"100%"} : {}),...style}}/>;}
