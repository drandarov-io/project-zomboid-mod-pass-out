plugins {
    java
}

val zomboidjar: String by project
val zomboidjarsources: String by project
val zomboidlua: String by project
val zomboidmedia: String by project

dependencies {
    implementation(files(zomboidjar))
    implementation(files(zomboidjarsources))
    implementation(files(zomboidlua))
    implementation(files(zomboidmedia))
}

sourceSets.create("media") {
    java.srcDir("media")

    compileClasspath += sourceSets.main.get().compileClasspath
}

val buildWorkshop by tasks.registering {
    val buildPath = "$buildDir/workshop/${project.name}"
    val modPath = "$buildPath/Contents/mods/${project.name}"

    group = "build"
    outputs.dir("$buildDir/workshop")

    doLast {
        copy {
            from("workshop/preview.png", "workshop/workshop.txt")
            into(buildPath)
        }

        copy {
            from("workshop/poster.png", "workshop/mod.info")
            into(modPath)
        }
        copy {
            from("media")
            into("$modPath/media")
        }
    }
}

val localDeploy by tasks.registering {
    val localPath = "${System.getProperties()["user.home"]}/Zomboid/Workshop"

    group = "build"
    outputs.dir("$localPath/${project.name}")

    dependsOn(buildWorkshop)

    doLast {
        copy {
            from(buildWorkshop.get().outputs.files)
            into(localPath)
        }
    }
}


val localUndeploy by tasks.registering {
    val localPath = "${System.getProperties()["user.home"]}/Zomboid/Workshop"

    group = "build"

    doLast {
        delete(localDeploy.get().outputs.files)
    }
}
